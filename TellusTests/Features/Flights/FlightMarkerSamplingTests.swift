import MapKit
import Testing
@testable import Tellus

@Suite
struct FlightMarkerSamplingTests {
    @Test func zoomedOutFlightsFillTheCapAndIncludeSparseAreas() {
        let denseTraffic = (0..<600).map {
            FlightMarker(id: "center-\($0)", latitude: 0, longitude: Double($0) / 1_000,
                         track: nil, source: .openSky)
        }
        let sparseTraffic = [
            FlightMarker(id: "northwest", latitude: 65, longitude: -140, track: nil, source: .openSky),
            FlightMarker(id: "northeast", latitude: 65, longitude: 140, track: nil, source: .openSky),
            FlightMarker(id: "southwest", latitude: -65, longitude: -140, track: nil, source: .openSky),
            FlightMarker(id: "southeast", latitude: -65, longitude: 140, track: nil, source: .openSky),
        ]
        let selected = FlightMarker(id: "selected", latitude: 0, longitude: 0, track: nil, source: .openSky)
        let flights = denseTraffic + sparseTraffic + [selected]

        let sample = flights.distributed(in: .world, limit: 500, keeping: selected.id)
        let sampledIDs = Set(sample.markers.map(\.id))

        #expect(sample.visibleCount == 605)
        #expect(sample.markers.count == 500)
        #expect(sampledIDs.count == 500)
        #expect(Set(sparseTraffic.map(\.id)).isSubset(of: sampledIDs))
        #expect(sampledIDs.contains(selected.id))
        #expect(Array(flights.reversed()).distributed(in: .world, limit: 500, keeping: selected.id).markers == sample.markers)
    }

    @Test func flightSamplingUsesBothSidesOfTheDateLineAndClipsToTheViewport() {
        let topLeft = MKMapPoint(CLLocationCoordinate2D(latitude: 20, longitude: 165))
        let bottom = MKMapPoint(CLLocationCoordinate2D(latitude: -20, longitude: 165))
        let viewport = MKMapRect(x: topLeft.x, y: topLeft.y,
                                 width: MKMapRect.world.width / 12, height: bottom.y - topLeft.y)
        let east = FlightMarker(id: "east", latitude: 0, longitude: 172, track: nil, source: .openSky)
        let west = FlightMarker(id: "west", latitude: 0, longitude: -172, track: nil, source: .openSky)
        let outside = FlightMarker(id: "outside", latitude: 0, longitude: -155, track: nil, source: .openSky)
        let north = FlightMarker(id: "north", latitude: 25, longitude: 172, track: nil, source: .openSky)
        let flights = [east, west, outside, north]

        let capped = flights.distributed(in: viewport, limit: 1, keeping: west.id)
        #expect(capped.visibleCount == 2)
        #expect(capped.markers == [west])

        let uncapped = flights.distributed(in: viewport, limit: 500)
        #expect(uncapped.visibleCount == 2)
        #expect(uncapped.markers == [east, west])
    }
}
