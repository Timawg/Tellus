import Foundation
import MapKit
import Observation
import SwiftUI
import Testing
@testable import Tellus

@MainActor
@Suite
struct MainMapViewModelTests {
    @Test func loadingCountriesSortsThemAndSelectsOne() async throws {
        let countries = try [testCountry("Japan", "JP", "JPN"), testCountry("Canada", "CA", "CAN")]
        let data = try JSONEncoder().encode(countries)
        let model = makeModel { request in
            #expect(request.url?.lastPathComponent == "countries.json")
            return data
        }

        await model.retrieveCountries()

        #expect(model.countries.compactMap { $0.name?.common } == ["Canada", "Japan"])
        let selected = try #require(model.current)
        #expect(model.countries.contains(selected))
        #expect(model.loadingError == nil)
    }

    @Test func loadingFailureKeepsSelectionAndRetryClearsError() async throws {
        let canada = try testCountry("Canada", "CA", "CAN")
        let japan = try testCountry("Japan", "JP", "JPN")
        let data = try JSONEncoder().encode([japan])
        let network = FailOnceNetwork(response: data)
        let model = makeModel { request in
            try await network.respond(to: request)
        }
        model.countries = [canada]
        model.current = canada

        await model.retrieveCountries()
        #expect(model.loadingError != nil)
        #expect(model.countries == [canada])
        #expect(model.current == canada)

        await model.retrieveCountries()
        #expect(model.loadingError == nil)
        #expect(model.current?.cca2 == "JP")
    }

    @Test func loadsAndPersistsInjectedPreferences() async throws {
        let passport = try testCountry("Sweden", "SE", "SWE", currencies: ["SEK"])
        let preferences = MemoryPreferences(nationality: passport, layers: [.earthAtNight: true, .cables: true])
        let model = makeModel(preferences: preferences)

        #expect(model.nationality == passport)
        #expect(model.showsEarthAtNight)
        #expect(model.cableLayer.isEnabled)
        #expect(!model.flights.showsFlights)
        #expect(!model.hazardLayer.isEnabled)
        #expect(!model.showsPowerGrid)
        #expect(!model.showsVIIRSImagery)
        #expect(!model.showsAurora)

        model.showsEarthAtNight = false
        model.showsPowerGrid = true
        model.showsVIIRSImagery = true
        model.showsAurora = true
        model.cableLayer.isEnabled = false
        model.nationality = nil

        let reopened = makeModel(preferences: preferences)
        #expect(reopened.nationality == nil)
        #expect(!reopened.showsEarthAtNight)
        #expect(!reopened.cableLayer.isEnabled)
        #expect(reopened.showsPowerGrid)
        #expect(reopened.showsVIIRSImagery)
        #expect(reopened.showsAurora)
    }

    @Test func defaultsStorePreservesLegacyNightSettingsAndPassportFormat() async throws {
        let suite = "TellusTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let passport = try testCountry("Sweden", "SE", "SWE")
        defaults.set(try JSONEncoder().encode(passport), forKey: "nationality")
        defaults.set(true, forKey: "showsNightLights")
        let preferences = UserDefaultsMapPreferencesStore(defaults: defaults)
        let model = makeModel(preferences: preferences)

        #expect(model.nationality?.cca2 == "SE")
        #expect(model.showsEarthAtNight)
        #expect(model.flights.showsFlights)
        #expect(model.hazardLayer.isEnabled)
        #expect(!model.cableLayer.isEnabled)
        #expect(!model.showsAurora)

        model.showsEarthAtNight = false
        model.nationality = nil

        #expect(defaults.data(forKey: "nationality") == nil)
        #expect(!makeModel(preferences: preferences).showsEarthAtNight)
    }

    @Test func countryWithoutBorderUsesAreaBasedRegion() async throws {
        let model = makeModel()
        model.current = try testCountry("Test Island", "ZZ", "ZZZ")

        await model.refreshDestination()

        #expect(model.selectedBorder == nil)
        #expect(model.region.center.latitude == 12)
        #expect(model.region.center.longitude == 34)
        #expect(model.region.span.latitudeDelta == 1)
        #expect(model.region.span.longitudeDelta == 2)
    }

    @Test func flightPollingPublishesBothFeedsAndDisablingClearsThem() async throws {
        let preferences = MemoryPreferences(layers: [.flights: true])
        let model = makeModel(preferences: preferences) { request in
            switch request.url?.path {
            case "/api/states/all":
                return Data(#"{"time":1,"states":[["abc123","FLIGHT","Sweden",1,1,10,20,null,false,null,null,null,null,null,null,false,0,null]]}"#.utf8)
            case "/v2/mil":
                return Data(#"{"ac":[{"hex":"def456","lat":21,"lon":11}]}"#.utf8)
            default:
                throw URLError(.unsupportedURL)
            }
        }
        let flights = model.flights
        defer { flights.setMapActive(false) }

        let publishedFlights = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        withObservationTracking {
            _ = flights.markerSnapshot
        } onChange: {
            publishedFlights.continuation.yield(())
        }
        model.updateViewport(.world)
        flights.setMapActive(true)
        try await requireSignal(from: publishedFlights.stream, "Flight annotations should be published")

        #expect(Set(flights.markerSnapshot.markers.map(\.id)) == ["abc123", "def456"])
        #expect(flights.totalFlightCount == 2)
        #expect(flights.flight(for: "ABC123")?.source == .openSky)
        #expect(flights.flight(for: "def456")?.source == .adsbLolMilitary)

        flights.selectedFlightID = "abc123"
        #expect(flights.selection?.id == "abc123")
        flights.showsFlights = false

        #expect(!preferences[.flights])
        #expect(flights.selection == nil)
        #expect(flights.markerSnapshot.markers.isEmpty)
        #expect(flights.flight(for: "abc123") == nil)
        #expect(flights.totalFlightCount == 0)
    }

    @Test func mapReusesAnnotationsWhenUpdatingFiveHundredFlightMarkers() throws {
        let mapView = MKMapView()
        let markers = (0..<500).map {
            FlightMarker(id: "flight-\($0)", latitude: 50, longitude: Double($0) / 100,
                         track: 90, source: .openSky)
        }
        func parent(_ snapshot: FlightMarkerSnapshot, selectedCableID: String? = nil) -> MapRepresentable {
            MapRepresentable(
                region: .constant(mapView.region),
                selectedFlightID: .constant(nil),
                flightMarkers: snapshot,
                selectedCableID: selectedCableID,
                regionWillChange: {},
                regionDidChange: { _ in }
            )
        }

        let original = FlightMarkerSnapshot(markers)
        let coordinator = MainMapCoordinator(parent: parent(original))
        coordinator.update(mapView, parent: parent(original))
        #expect(mapView.annotations.count == 500)
        let first = try #require(mapView.annotations.compactMap { $0 as? FlightAnnotation }
            .first { $0.id == "flight-0" })

        coordinator.update(mapView, parent: parent(original, selectedCableID: "unrelated-selection"))
        #expect(mapView.annotations.count == 500)

        let changed = FlightMarker(id: first.id, latitude: 50, longitude: 0, track: 120, source: .adsbLolMilitary)
        let added = FlightMarker(id: "flight-new", latitude: 51, longitude: 0, track: nil, source: .openSky)
        let next = FlightMarkerSnapshot([changed] + Array(markers.dropFirst(2)) + [added])
        coordinator.update(mapView, parent: parent(next))

        let current = mapView.annotations.compactMap { $0 as? FlightAnnotation }
        #expect(current.count == 500)
        #expect(current.first { $0.id == first.id } === first)
        #expect(first.track == 120)
        #expect(first.source == .adsbLolMilitary)
        #expect(!current.contains { $0.id == "flight-1" })
        #expect(current.contains { $0.id == added.id })
    }

    private func makeModel(
        preferences: MapPreferencesStore = MemoryPreferences(),
        respond: @escaping @Sendable (URLRequest) async throws -> Data = { _ in
            throw URLError(.unsupportedURL)
        }
    ) -> MainMapViewModel {
        MainMapServices.makeViewModel(networkService: StubNetwork(respond: respond), preferences: preferences)
    }
}

private actor FailOnceNetwork {
    let response: Data
    private var failed = false

    init(response: Data) {
        self.response = response
    }

    func respond(to request: URLRequest) throws -> Data {
        if !failed {
            failed = true
            throw URLError(.notConnectedToInternet)
        }
        return response
    }
}
