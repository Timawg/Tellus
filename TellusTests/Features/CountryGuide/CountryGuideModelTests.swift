import Foundation
import Testing
@testable import Tellus

@MainActor
@Suite
struct CountryGuideModelTests {
    @Test func lateDestinationDataCannotReplaceTheCurrentGuide() async throws {
        let requestedFrance = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let release = AsyncStream<Void>.makeStream()
        let network = StubNetwork { request in
            guard let url = request.url, url.path.hasSuffix("/outages/events"),
                  let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "entityCode" })?.value else {
                throw URLError(.unsupportedURL)
            }
            if code == "FR" {
                requestedFrance.continuation.yield(())
                var iterator = release.stream.makeAsyncIterator()
                _ = await iterator.next()
            }
            let start = code == "FR" ? 100 : 300
            return Data("""
                {"data":[{"start":\(start),"duration":60,"datasource":"bgp"},
                         {"start":\(start + 10),"duration":60,"datasource":"gtr"}]}
                """.utf8)
        }
        let model = CountryGuideModel(services: CountryGuideServices(networkService: network))
        let france = try testCountry("France", "FR", "FRA")
        let sweden = try testCountry("Sweden", "SE", "SWE")
        let countries = [france, sweden]
        model.updateSelection(destination: france, passport: nil)
        let olderRefresh = Task { await model.refreshDestination(france, countries: countries) }
        defer {
            olderRefresh.cancel()
            release.continuation.finish()
        }

        try await requireSignal(from: requestedFrance.stream, "The first destination should start loading")
        model.updateSelection(destination: sweden, passport: nil)
        await model.refreshDestination(sweden, countries: countries)
        release.continuation.finish()
        await olderRefresh.value
        #expect(model.internetOutages.map(\.start) == [Date(timeIntervalSince1970: 300)])

        model.updateSelection(destination: sweden, passport: france)
        await model.refreshPassportInformation(destination: sweden, passport: france)
        #expect(model.internetOutages.map(\.start) == [Date(timeIntervalSince1970: 300)])
    }

    @Test func passportRefreshPublishesVisaAndOnlyDestinationCurrencies() async throws {
        let network = StubNetwork { request in
            switch request.url?.lastPathComponent {
            case "passport-index-tidy-iso2.csv":
                return Data("Passport,Destination,Requirement\nSE,FR,90".utf8)
            case "sek.json":
                return Data(#"{"date":"2026-11-01","sek":{"eur":0.09,"usd":0.11,"sek":1}}"#.utf8)
            default:
                throw URLError(.unsupportedURL)
            }
        }
        let passport = try testCountry("Sweden", "SE", "SWE", currencies: ["SEK"])
        let destination = try testCountry("France", "FR", "FRA", currencies: ["EUR", "SEK"])

        let model = CountryGuideModel(services: CountryGuideServices(networkService: network))
        model.updateSelection(destination: destination, passport: passport)
        await model.refreshPassportInformation(destination: destination, passport: passport)

        #expect(model.admissoryStatus?.status == "visa-free")
        #expect(model.admissoryStatus?.dur == "90")
        #expect(model.exchangeRates == [
            ExchangeRate(home: "SEK", destination: "EUR", rate: 0.09, date: "2026-11-01"),
        ])
    }

    @Test func lateRateFailureDoesNotClearNewPassportRates() async throws {
        let requestedSwedishRates = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let release = AsyncStream<Void>.makeStream()
        let network = StubNetwork { request in
            switch request.url?.lastPathComponent {
            case "sek.json":
                if request.url?.host == "latest.currency-api.pages.dev" {
                    requestedSwedishRates.continuation.yield(())
                    var iterator = release.stream.makeAsyncIterator()
                    _ = await iterator.next()
                }
                throw URLError(.notConnectedToInternet)
            case "usd.json":
                return Data(#"{"date":"2026-11-01","usd":{"eur":0.86}}"#.utf8)
            default:
                throw URLError(.unsupportedURL)
            }
        }
        let destination = try testCountry("France", "FR", "FRA", currencies: ["EUR"])
        let passport = try testCountry("Sweden", "SE", "SWE", currencies: ["SEK"])
        let nextPassport = try testCountry("United States", "US", "USA", currencies: ["USD"])
        let model = CountryGuideModel(services: CountryGuideServices(networkService: network))
        model.updateSelection(destination: destination, passport: passport)
        let olderRefresh = Task { await model.refreshPassportInformation(destination: destination, passport: passport) }
        defer {
            olderRefresh.cancel()
            release.continuation.finish()
        }

        try await requireSignal(from: requestedSwedishRates.stream, "The Swedish rate request should start")
        model.updateSelection(destination: destination, passport: nextPassport)
        await model.refreshPassportInformation(destination: destination, passport: nextPassport)
        release.continuation.finish()
        await olderRefresh.value

        #expect(model.exchangeRates == [
            ExchangeRate(home: "USD", destination: "EUR", rate: 0.86, date: "2026-11-01"),
        ])
    }
}
