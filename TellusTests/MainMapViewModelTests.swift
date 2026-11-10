import Foundation
import MapKit
import Observation
import Testing
@testable import Tellus

@MainActor
@Suite
struct MainMapViewModelTests {
    @Test func loadingCountriesSortsThemAndSelectsOne() async throws {
        let countries = try [country("Japan", "JP", "JPN"), country("Canada", "CA", "CAN")]
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
        let canada = try country("Canada", "CA", "CAN")
        let japan = try country("Japan", "JP", "JPN")
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
        let passport = try country("Sweden", "SE", "SWE", currencies: ["SEK"])
        let preferences = MemoryPreferences(nationality: passport, layers: [.earthAtNight: true, .cables: true])
        let model = makeModel(preferences: preferences)

        #expect(model.nationality == passport)
        #expect(model.homeCurrency == "SEK")
        #expect(model.showsEarthAtNight)
        #expect(model.showsCables)
        #expect(!model.showsFlights)
        #expect(!model.showsHazards)
        #expect(!model.showsPowerGrid)
        #expect(!model.showsVIIRSImagery)
        #expect(!model.showsAurora)

        model.showsEarthAtNight = false
        model.showsPowerGrid = true
        model.showsVIIRSImagery = true
        model.showsAurora = true
        model.showsCables = false
        model.nationality = nil

        let reopened = makeModel(preferences: preferences)
        #expect(reopened.nationality == nil)
        #expect(!reopened.showsEarthAtNight)
        #expect(!reopened.showsCables)
        #expect(reopened.showsPowerGrid)
        #expect(reopened.showsVIIRSImagery)
        #expect(reopened.showsAurora)
    }

    @Test func defaultsStorePreservesLegacyNightSettingsAndPassportFormat() async throws {
        let suite = "TellusTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let passport = try country("Sweden", "SE", "SWE")
        defaults.set(try JSONEncoder().encode(passport), forKey: "nationality")
        defaults.set(true, forKey: "showsNightLights")
        let preferences = UserDefaultsMapPreferencesStore(defaults: defaults)
        let model = makeModel(preferences: preferences)

        #expect(model.nationality?.cca2 == "SE")
        #expect(model.showsEarthAtNight)
        #expect(model.showsFlights)
        #expect(model.showsHazards)
        #expect(!model.showsCables)
        #expect(!model.showsAurora)

        model.showsEarthAtNight = false
        model.nationality = nil

        #expect(defaults.data(forKey: "nationality") == nil)
        #expect(!makeModel(preferences: preferences).showsEarthAtNight)
    }

    @Test func auroraForecastUsesValidTimeAndProjectsBothHemispheres() async throws {
        let model = makeModel { request in
            #expect(request.url?.absoluteString == "https://services.swpc.noaa.gov/json/ovation_aurora_latest.json")
            return Data("""
                {"Observation Time":"2026-11-06T23:36:00Z","Forecast Time":"2026-11-07T00:41:00Z",
                 "coordinates":[[350,65,12],[349,65,13],[45,-60,28],[180,70,60],[0,0,0],[0,90,90]]}
                """.utf8)
        }

        let overlay = try await model.loadAuroraForecast()

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

    @Test func eurostatPriceComparisonUsesLatestSharedYearAndKeepsMissingCategories() async throws {
        let model = makeModel { request in
            #expect(request.url?.lastPathComponent == "prc_ppp_ind_1")
            let query = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
            #expect(query.contains(URLQueryItem(name: "indic_ppp", value: "PLI_EU27_2020")))
            let categories = Set(query.filter { $0.name == "ppp_cat18" }.compactMap(\.value))
            #expect(categories == ["E011", "A0101", "A0104", "A0107", "A0111"])
            return Data("""
                {
                  "id": ["freq", "indic_ppp", "ppp_cat18", "geo", "time"],
                  "size": [1, 1, 3, 4, 3],
                  "dimension": {
                    "freq": {"category": {"index": {"A": 0}}},
                    "indic_ppp": {"category": {"index": {"PLI_EU27_2020": 0}}},
                    "ppp_cat18": {"category": {"index": {"A0101": 0, "A0107": 1, "E011": 2}}},
                    "geo": {"category": {"index": {"EU27_2020": 0, "SE": 1, "EL": 2, "UK": 3},
                                         "label": {"SE": "Sweden", "EL": "Greece", "UK": "United Kingdom"}}},
                    "time": {"category": {"index": {"2023": 0, "2024": 1, "2025": 2}}}
                  },
                  "value": {"4": 100, "7": 110, "16": 120, "18": 100,
                            "24": 100, "25": 100, "26": 100, "28": 120, "29": 121,
                            "30": 85, "31": 90, "35": 123}
                }
                """.utf8)
        }

        let prices = try await model.loadPriceLevels()
        let greece = try #require(prices.comparison(for: "GR", against: "SE"))
        #expect(greece.year == 2024)
        let greeceOverall = try #require(greece.changes[.overall])
        let greeceGroceries = try #require(greece.changes[.groceries])
        #expect(abs(greeceOverall + 0.25) <= 0.0001)
        #expect(abs(greeceGroceries - 0.10) <= 0.0001)
        #expect(greece.changes[.transport] == nil)
        #expect(prices.referenceAreas(for: "GR").map(\.id) == ["EU27_2020", "SE"])

        let sweden = try #require(prices.comparison(for: "SE", against: EurostatPriceLevels.euAverageCode))
        #expect(sweden.year == 2025)
        let swedenOverall = try #require(sweden.changes[.overall])
        #expect(abs(swedenOverall - 0.21) <= 0.0001)
        #expect(prices.comparison(for: "GB", against: EurostatPriceLevels.euAverageCode)?.year == 2025)
        #expect(prices.comparison(for: "CA", against: EurostatPriceLevels.euAverageCode) == nil)
    }

    @Test func passportRefreshPublishesVisaAndOnlyDestinationCurrencies() async throws {
        let model = makeModel { request in
            switch request.url?.lastPathComponent {
            case "passport-index-tidy-iso2.csv":
                return Data("Passport,Destination,Requirement\nSE,FR,90".utf8)
            case "sek.json":
                return Data(#"{"date":"2026-11-01","sek":{"eur":0.09,"usd":0.11,"sek":1}}"#.utf8)
            default:
                throw URLError(.unsupportedURL)
            }
        }
        model.nationality = try country("Sweden", "SE", "SWE", currencies: ["SEK"])
        model.current = try country("France", "FR", "FRA", currencies: ["EUR", "SEK"])

        await model.refreshPassportInformation()

        #expect(model.admissoryStatus?.status == "visa-free")
        #expect(model.admissoryStatus?.dur == "90")
        #expect(model.exchangeRates == [
            ExchangeRate(home: "SEK", destination: "EUR", rate: 0.09, date: "2026-11-01"),
        ])
    }

    @Test func lateRateFailureDoesNotClearNewPassportRates() async throws {
        let requestedSwedishRates = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let release = AsyncStream<Void>.makeStream()
        let model = makeModel { request in
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
        model.current = try country("France", "FR", "FRA", currencies: ["EUR"])
        model.nationality = try country("Sweden", "SE", "SWE", currencies: ["SEK"])
        let nextPassport = try country("United States", "US", "USA", currencies: ["USD"])
        let olderRefresh = Task { await model.refreshPassportInformation() }
        defer {
            olderRefresh.cancel()
            release.continuation.finish()
        }

        try await requireSignal(from: requestedSwedishRates.stream, "The Swedish rate request should start")
        model.nationality = nextPassport
        await model.refreshPassportInformation()
        release.continuation.finish()
        await olderRefresh.value

        #expect(model.exchangeRates == [
            ExchangeRate(home: "USD", destination: "EUR", rate: 0.86, date: "2026-11-01"),
        ])
    }

    @Test func countryWithoutBorderUsesAreaBasedRegion() async throws {
        let model = makeModel()
        model.current = try country("Test Island", "ZZ", "ZZZ")

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
        defer { model.stopUpdatingFlightData() }

        let publishedFlights = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        withObservationTracking {
            _ = model.flightAnnotations
        } onChange: {
            publishedFlights.continuation.yield(())
        }
        model.startUpdatingFlightData()
        try await requireSignal(from: publishedFlights.stream, "Flight annotations should be published")

        #expect(Set(model.flightAnnotations.map(\.id)) == ["abc123", "def456"])
        #expect(model.totalFlightCount == 2)
        #expect(model.flight(for: "ABC123")?.source == .openSky)
        #expect(model.flight(for: "def456")?.source == .adsbLolMilitary)

        let selectedFlight = try #require(model.flightAnnotations.first)
        model.selectedFlight = selectedFlight
        model.showsFlights = false

        #expect(!preferences[.flights])
        #expect(model.selectedFlight == nil)
        #expect(model.flightAnnotations.isEmpty)
        #expect(model.flight(for: "abc123") == nil)
        #expect(model.totalFlightCount == 0)
    }

    private func requireSignal(from stream: AsyncStream<Void>, _ comment: Comment) async throws {
        let signalled = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                var iterator = stream.makeAsyncIterator()
                return await iterator.next() != nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(5))
                return false
            }
            defer { group.cancelAll() }
            return await group.next() ?? false
        }
        try #require(signalled, comment)
    }

    private func makeModel(
        preferences: MapPreferencesStore = MemoryPreferences(),
        respond: @escaping @Sendable (URLRequest) async throws -> Data = { _ in
            throw URLError(.unsupportedURL)
        }
    ) -> MainMapViewModel {
        MainMapViewModel(services: MainMapServices(networkService: StubNetwork(respond: respond)), preferences: preferences)
    }

    private func country(
        _ name: String,
        _ code: String,
        _ alpha3: String,
        currencies: [String] = []
    ) throws -> Country {
        let fixture: [String: Any] = [
            "name": ["common": name, "official": name, "native": [:]],
            "cca2": code,
            "cca3": alpha3,
            "latlng": [12, 34],
            "area": 12_100,
            "translations": [:],
            "currencies": Dictionary(uniqueKeysWithValues: currencies.map { ($0, ["name": $0]) }),
        ]
        return try JSONDecoder().decode(Country.self, from: JSONSerialization.data(withJSONObject: fixture))
    }
}

private final class MemoryPreferences: MapPreferencesStore {
    var nationality: Country?
    private var layers: [MapLayer: Bool]

    init(nationality: Country? = nil, layers: [MapLayer: Bool] = [:]) {
        self.nationality = nationality
        self.layers = layers
    }

    subscript(layer: MapLayer) -> Bool {
        get { layers[layer, default: false] }
        set { layers[layer] = newValue }
    }
}

private struct StubNetwork: NetworkServiceProtocol {
    let respond: @Sendable (URLRequest) async throws -> Data

    func send(request: URLRequest) async throws -> Data {
        try await respond(request)
    }

    func send<T: Decodable>(request: URLRequest) async throws -> T {
        let data = try await send(request: request)
        return try JSONDecoder().decode(T.self, from: data)
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
