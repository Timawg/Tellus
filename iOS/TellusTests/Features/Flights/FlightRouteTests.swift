import MapKit
import Observation
import SwiftUI
import Testing
@testable import Tellus

@MainActor
@Suite
struct FlightRouteTests {
    @Test func mapSkipsInvalidAndZeroLengthRoutes() throws {
        let route = makeRoute(destinationLongitude: 15)
        let aircraft = CLLocationCoordinate2D(latitude: 22, longitude: 10)
        let coordinates = try #require(route.mapCoordinates(through: aircraft))
        #expect(coordinates.map(\.latitude) == [20, 22, 20])
        #expect(coordinates.map(\.longitude) == [5, 10, 15])
        #expect(makeRoute(destinationLongitude: 5).mapCoordinates(through: aircraft) == nil)
        #expect(makeRoute(destinationLongitude: 181).mapCoordinates(through: aircraft) == nil)
        #expect(route.mapCoordinates(through: .init(latitude: 91, longitude: 10)) == nil)
    }

    @Test func routeFollowsSelectedMarkerAndClearsOnDismissal() throws {
        let map = MKMapView()
        let route = makeRoute(destinationLongitude: 15)
        func parent(route: FlightRoute?, markers: [FlightMarker]) -> MapRepresentable {
            MapRepresentable(
                region: .constant(map.region),
                selectedFlightID: .constant(route == nil ? nil : "abc123"),
                flightMarkers: FlightMarkerSnapshot(markers),
                flightRoute: route,
                regionWillChange: {},
                regionDidChange: { _ in }
            )
        }

        let marker = FlightMarker(id: "abc123", latitude: 22, longitude: 10, track: 90, source: .openSky)
        let initial = parent(route: route, markers: [marker])
        let coordinator = MainMapCoordinator(parent: initial)
        coordinator.update(map, parent: initial)
        let overlay = try #require(map.overlays(in: .aboveLabels).first as? MKGeodesicPolyline)
        let renderer = try #require(coordinator.mapView(map, rendererFor: overlay) as? MKPolylineRenderer)
        #expect(renderer.polyline === overlay)
        #expect(contains(marker.coordinate, in: overlay))

        let otherMarker = FlightMarker(id: "def456", latitude: 25, longitude: 12, track: 90, source: .openSky)
        coordinator.update(map, parent: parent(route: route, markers: [marker, otherMarker]))
        #expect(map.overlays.count == 1)
        #expect(map.overlays.first === overlay)

        let movedMarker = FlightMarker(id: marker.id, latitude: 21, longitude: 12, track: 90, source: .openSky)
        coordinator.update(map, parent: parent(route: route, markers: [movedMarker]))
        let movedOverlay = try #require(map.overlays(in: .aboveLabels).first as? MKGeodesicPolyline)
        #expect(map.overlays.count == 1)
        #expect(movedOverlay !== overlay)
        #expect(contains(movedMarker.coordinate, in: movedOverlay))
        #expect(!contains(marker.coordinate, in: movedOverlay))

        coordinator.update(map, parent: parent(route: nil, markers: [movedMarker]))
        #expect(map.overlays.isEmpty)
        #expect(map.annotations.count == 1)
    }

    private func contains(_ coordinate: CLLocationCoordinate2D, in overlay: MKGeodesicPolyline) -> Bool {
        let point = MKMapPoint(coordinate)
        let points = UnsafeBufferPointer(start: overlay.points(), count: overlay.pointCount)
        return points.contains { abs($0.x - point.x) < 1 && abs($0.y - point.y) < 1 }
    }

    @Test func routeAppearsBeforeAircraftDetailsAndClearsWhenSelectionChanges() async throws {
        let releaseAircraft = AsyncStream<Void>.makeStream()
        let flights = makeFlights { request in
            switch request.url?.path {
            case "/v0/callsign/FLIGHT":
                return Self.routeResponse
            case "/v0/aircraft/abc123":
                var iterator = releaseAircraft.stream.makeAsyncIterator()
                _ = await iterator.next()
                return Data(#"{"response":{"aircraft":{"registration":"SE-ABC"}}}"#.utf8)
            default:
                throw URLError(.unsupportedURL)
            }
        }
        defer { flights.setMapActive(false) }
        try await startPolling(flights)
        flights.selectedFlightID = "abc123"
        let selection = try #require(flights.selection)
        let routeLoaded = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        withObservationTracking {
            _ = flights.selectedMapRoute
        } onChange: {
            routeLoaded.continuation.yield(())
        }

        let load = Task { await flights.loadFlightDetails(for: selection) }
        defer { releaseAircraft.continuation.finish() }
        try await requireSignal(from: routeLoaded.stream, "Route should be published before registration")
        #expect(flights.selectedMapRoute?.callsign == "FLIGHT")
        #expect(flights.isLoadingFlightDetails)

        releaseAircraft.continuation.finish()
        await load.value
        #expect(flights.selectedAircraft?.registration == "SE-ABC")

        flights.selection = nil
        #expect(flights.selectedMapRoute == nil)
        #expect(flights.selectedRoute != nil)

        flights.selectedFlightID = "abc123"
        #expect(flights.selectedMapRoute == nil)
        #expect(flights.selectedRoute == nil)
    }

    @Test func pendingRouteCannotPublishAfterTheSameAircraftIsReselected() async throws {
        let routeRequested = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let releaseRoute = AsyncStream<Void>.makeStream()
        let flights = makeFlights { request in
            guard request.url?.path == "/v0/callsign/FLIGHT" else { throw URLError(.unsupportedURL) }
            routeRequested.continuation.yield(())
            var iterator = releaseRoute.stream.makeAsyncIterator()
            _ = await iterator.next()
            return Self.routeResponse
        }
        defer { flights.setMapActive(false) }
        try await startPolling(flights)
        flights.selectedFlightID = "abc123"
        let firstSelection = try #require(flights.selection)

        let load = Task { await flights.loadFlightDetails(for: firstSelection) }
        defer { releaseRoute.continuation.finish() }
        try await requireSignal(from: routeRequested.stream, "First route request should be in flight")

        flights.selectedFlightID = nil
        flights.selectedFlightID = "abc123"
        releaseRoute.continuation.finish()
        await load.value
        #expect(flights.selectedMapRoute == nil)

        await flights.loadFlightDetails(for: flights.selection)
        #expect(flights.selectedMapRoute?.callsign == "FLIGHT")
    }

    private func startPolling(_ flights: LiveFlightsModel) async throws {
        let published = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        withObservationTracking {
            _ = flights.markerSnapshot
        } onChange: {
            published.continuation.yield(())
        }
        flights.updateViewport(.world)
        flights.setMapActive(true)
        try await requireSignal(from: published.stream, "Test aircraft should be on the map")
    }

    private func makeFlights(
        respond: @escaping @Sendable (URLRequest) async throws -> Data
    ) -> LiveFlightsModel {
        let network = StubNetwork { request in
            switch request.url?.path {
            case "/api/states/all":
                Data(#"""
                    {"time":1,"states":[
                        ["abc123","FLIGHT","Sweden",1,1,10,20,null,false,null,null,null,null,null,null,false,0,null]
                    ]}
                    """#.utf8)
            case "/v2/mil":
                Data(#"{"ac":[]}"#.utf8)
            default:
                try await respond(request)
            }
        }
        let preferences = MemoryPreferences(layers: [.flights: true])
        return MainMapServices.makeViewModel(networkService: network, preferences: preferences).flights
    }

    private func makeRoute(destinationLongitude: Double) -> FlightRoute {
        func airport(_ name: String, longitude: Double) -> FlightRoute.Airport {
            .init(name: name, municipality: nil, countryName: nil, iataCode: nil, icaoCode: nil,
                  latitude: 20, longitude: longitude)
        }
        return .init(
            callsign: "FLIGHT",
            callsignIata: nil,
            airline: nil,
            origin: airport("Origin", longitude: 5),
            destination: airport("Destination", longitude: destinationLongitude)
        )
    }

    nonisolated private static let routeResponse = Data(#"""
        {"response":{"flightroute":{"callsign":"FLIGHT",
            "origin":{"name":"Origin","latitude":20,"longitude":5},
            "destination":{"name":"Destination","latitude":20,"longitude":15}}}}
        """#.utf8)
}
