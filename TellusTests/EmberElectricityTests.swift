import Foundation
import Testing
@testable import Tellus

@Suite
struct EmberElectricityTests {
    @Test func selectsLatestGenerationYearAndKeepsNetTradeSeparate() throws {
        let profiles = try EmberElectricityDataset.profiles(from: Self.dataset)
        let sweden = try #require(profiles["SWE"])

        #expect(sweden.year == 2025)
        #expect(sweden.totalGenerationTWh == 120)
        #expect(sweden.netImportsTWh == -12)
        #expect(sweden.fuels == [
            .init(name: "Hydro", generationTWh: 90, sharePercent: 75),
            .init(name: "Wind", generationTWh: 30, sharePercent: nil),
        ])

        let lesotho = try #require(profiles["LSO"])
        #expect(lesotho.year == 2024)
        #expect(lesotho.totalGenerationTWh == 0)
        #expect(lesotho.netImportsTWh == 0.58)
        #expect(lesotho.fuels.isEmpty)
        #expect(profiles["ATA"] == nil)
        #expect(profiles.count == 3)
    }

    @Test func refreshIsSharedAndParsedResultsPersistAcrossServiceInstances() async throws {
        let cacheURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: cacheURL) }
        let network = StubNetwork(data: Self.dataset)
        let service = EmberElectricityService(networkService: network, cacheURL: cacheURL)

        async let sweden = service.getProfile(countryCode: "swe")
        async let lesotho = service.getProfile(countryCode: "LSO")
        let (first, second) = try await (sweden, lesotho)
        #expect(first?.year == 2025)
        #expect(second?.year == 2024)

        let reopened = EmberElectricityService(networkService: network, cacheURL: cacheURL)
        let cached = try await reopened.getProfile(countryCode: "SWE")
        #expect(cached == first)
        let kosovo = try await reopened.getProfile(countryCode: "UNK")
        #expect(kosovo?.totalGenerationTWh == 5.864)
        let requests = await network.requests
        #expect(requests.count == 1)
        #expect(requests.first?.lastPathComponent == "release_generation_yearly_global.csv")
    }

    @Test func rejectsUnrecognizedSchema() {
        #expect(throws: (any Error).self) {
            _ = try EmberElectricityDataset.profiles(from: Data("Area,Year\nSweden,2025".utf8))
        }
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
            requests.append(try #require(request.url))
            return data
        }

        func send<T: Decodable>(request: URLRequest) async throws -> T {
            throw URLError(.cannotDecodeContentData)
        }
    }
}
