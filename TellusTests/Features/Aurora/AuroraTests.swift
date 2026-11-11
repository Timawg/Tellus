import Foundation
import MapKit
import Testing
@testable import Tellus

@Suite
struct AuroraTests {
    @Test func auroraForecastUsesValidTimeAndProjectsBothHemispheres() async throws {
        let network = StubNetwork { request in
            #expect(request.url?.absoluteString == "https://services.swpc.noaa.gov/json/ovation_aurora_latest.json")
            return Data("""
                {"Observation Time":"2026-11-06T23:36:00Z","Forecast Time":"2026-11-07T00:41:00Z",
                 "coordinates":[[350,65,12],[349,65,13],[45,-60,28],[180,70,60],[0,0,0],[0,90,90]]}
                """.utf8)
        }

        let overlay = try await AuroraService(networkService: network).getForecast()

        let validAt = try Date("2026-11-07T00:41:00Z", strategy: .iso8601)
        #expect(overlay.validAt == validAt)
        #expect(!overlay.isOlder(at: overlay.validAt.addingTimeInterval(29 * 60)))
        #expect(overlay.isOlder(at: overlay.validAt.addingTimeInterval(30 * 60)))
        #expect(overlay.bands.count == 3)
        let green = try #require(overlay.bands[.green]?.first)
        #expect(overlay.bands[.green]?.count == 1)
        #expect(green.contains(MKMapPoint(CLLocationCoordinate2D(latitude: 65, longitude: -10))))
        #expect(green.contains(MKMapPoint(CLLocationCoordinate2D(latitude: 65, longitude: -11))))
        let teal = try #require(overlay.bands[.teal]?.first)
        #expect(teal.contains(MKMapPoint(CLLocationCoordinate2D(latitude: -60, longitude: 45))))
        let dateLine = try #require(overlay.bands[.amber]?.first)
        #expect(dateLine.minX < 0)
        #expect(dateLine.maxX > 0)
    }

    @Test func auroraForecastRejectsInvalidGridAndKeepsValidZeroGrid() throws {
        let date = Date.now
        #expect(throws: (any Error).self) {
            _ = try AuroraOverlay(validAt: date, coordinates: [])
        }
        #expect(throws: (any Error).self) {
            _ = try AuroraOverlay(validAt: date, coordinates: [[0, 0]])
        }
        #expect(throws: (any Error).self) {
            _ = try AuroraOverlay(validAt: date, coordinates: [[360, 0, 10]])
        }
        let zeroGrid = try AuroraOverlay(validAt: date, coordinates: [[0, 0, 0]])
        #expect(zeroGrid.bands.isEmpty)
    }
}
