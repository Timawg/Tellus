import Foundation
import Testing
@testable import Tellus

struct DemocracySafetyTests {
    @Test func bundledDemocracySeriesMatchTheAreasTheyDescribe() async throws {
        let store = DemocracyDatasetStore()
        let sweden = try await store.profile(countryCode: "swe")
        let observations = try #require(sweden.series.first?.observations)
        let latest = try #require(observations.last)
        #expect(observations.count == 10)
        #expect(observations.map(\.year) == Array((latest.year - 9)...latest.year))
        #expect(observations.allSatisfy { (0...1).contains($0.value) })

        let kosovo = try await store.profile(countryCode: "UNK")
        #expect(kosovo.series.map(\.id) == ["XKX"])

        let palestine = try await store.profile(countryCode: "PSE")
        #expect(palestine.series.map(\.area) == ["West Bank", "Gaza"])
        #expect(palestine.series.allSatisfy { !$0.observations.isEmpty })

        let unavailable = try await store.profile(countryCode: "ATA")
        #expect(unavailable.series.isEmpty)
    }

    @Test func homicideTrendKeepsReportedYearsAndZeros() async throws {
        let network = StubNetwork { request in
            let url = try #require(request.url)
            #expect(url.host == "api.worldbank.org")
            #expect(url.path == "/v2/country/SE/indicator/VC.IHR.PSRC.P5")
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
            #expect(query?.contains(URLQueryItem(name: "mrnev", value: "10")) == true)
            return Data("""
                [{"total":5},[
                    {"indicator":{"id":"VC.IHR.PSRC.P5"},"date":"2023","value":0},
                    {"indicator":{"id":"VC.IHR.PSRC.P5"},"date":"2022","value":null},
                    {"indicator":{"id":"VC.IHR.PSRC.P5"},"date":"2019","value":-1},
                    {"indicator":{"id":"VC.IHR.PSRC.P5"},"date":"2019","value":1.15},
                    {"indicator":{"id":"VC.IHR.PSRC.P5"},"date":"2020","value":-1}
                ]]
                """.utf8)
        }
        let service = CountryProfileService(networkService: network)
        let observations = try await service.getHomicideTrend(countryCode: "se")
        #expect(observations == [
            AnnualObservation(year: 2019, value: 1.15),
            AnnualObservation(year: 2023, value: 0)
        ])
    }

    @Test func unsupportedCountryHasNoHomicideData() async throws {
        let network = StubNetwork { _ in
            Data(#"[{"message":[{"id":"120","key":"Invalid value"}]}]"#.utf8)
        }
        let service = CountryProfileService(networkService: network)
        let observations = try await service.getHomicideTrend(countryCode: "AQ")
        #expect(observations.isEmpty)
    }
}
