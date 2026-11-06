import Foundation
import XCTest
@testable import Tellus

final class EmberElectricityTests: XCTestCase {
    func testSelectsLatestGenerationYearAndKeepsNetTradeSeparate() throws {
        let profiles = try EmberElectricityDataset.profiles(from: Self.dataset)
        let sweden = try XCTUnwrap(profiles["SWE"])

        XCTAssertEqual(sweden.year, 2025)
        XCTAssertEqual(sweden.totalGenerationTWh, 120)
        XCTAssertEqual(sweden.netImportsTWh, -12)
        XCTAssertEqual(sweden.fuels, [
            .init(name: "Hydro", generationTWh: 90, sharePercent: 75),
            .init(name: "Wind", generationTWh: 30, sharePercent: nil),
        ])

        let lesotho = try XCTUnwrap(profiles["LSO"])
        XCTAssertEqual(lesotho.year, 2024)
        XCTAssertEqual(lesotho.totalGenerationTWh, 0)
        XCTAssertEqual(lesotho.netImportsTWh, 0.58)
        XCTAssertTrue(lesotho.fuels.isEmpty)
        XCTAssertNil(profiles["ATA"])
        XCTAssertEqual(profiles.count, 3)
    }

    func testRefreshIsSharedAndParsedResultsPersistAcrossServiceInstances() async throws {
        let cacheURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: cacheURL) }
        let network = StubNetwork(data: Self.dataset)
        let service = EmberElectricityService(networkService: network, cacheURL: cacheURL)

        async let sweden = service.getProfile(countryCode: "swe")
        async let lesotho = service.getProfile(countryCode: "LSO")
        let (first, second) = try await (sweden, lesotho)
        XCTAssertEqual(first?.year, 2025)
        XCTAssertEqual(second?.year, 2024)

        let reopened = EmberElectricityService(networkService: network, cacheURL: cacheURL)
        let cached = try await reopened.getProfile(countryCode: "SWE")
        XCTAssertEqual(cached, first)
        let kosovo = try await reopened.getProfile(countryCode: "UNK")
        XCTAssertEqual(kosovo?.totalGenerationTWh, 5.864)
        let requests = await network.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.lastPathComponent, "release_generation_yearly_global.csv")
    }

    func testRejectsUnrecognizedSchema() {
        XCTAssertThrowsError(try EmberElectricityDataset.profiles(from: Data("Area,Year\nSweden,2025".utf8)))
    }

    private static let dataset = Data("""
        Area,ISO 3 code,Year,Electricity source,Is aggregated source,Generation (TWh),Share of generation (%)
        Sweden,SWE,2025,Wind,False,30,
        Sweden,SWE,2025,Net imports,False,-12,-10
        Sweden,SWE,2024,Total generation,True,100,100
        Sweden,SWE,2025,"Hydro, bioenergy and other renewables",True,90,75
        Sweden,SWE,2026,Wind,False,31,25
        Sweden,SWE,2025,Coal,False,0,0
        Sweden,SWE,2025,Hydro,False,90,75
        Sweden,SWE,2025,Total generation,True,120,100
        Lesotho,LSO,2024,Net imports,False,0.58,
        Lesotho,LSO,2024,Total generation,True,0,
        Kosovo,XKX,2025,Total generation,True,5.864,100
        World,,2025,Total generation,True,30000,100
        """.utf8)

    private actor StubNetwork: NetworkServiceProtocol {
        let data: Data
        private(set) var requests: [URL] = []

        init(data: Data) {
            self.data = data
        }

        func send(request: URLRequest) async throws -> Data {
            requests.append(try XCTUnwrap(request.url))
            return data
        }

        func send<T: Decodable>(request: URLRequest) async throws -> T {
            throw URLError(.cannotDecodeContentData)
        }
    }
}
