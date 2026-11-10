import Foundation
import MapKit
import Observation
import XCTest
@testable import Tellus

@MainActor
final class MainMapViewModelTests: XCTestCase {
    func testLoadingCountriesSortsThemAndSelectsOne() async throws {
        let countries = try [country("Japan", "JP", "JPN"), country("Canada", "CA", "CAN")]
        let data = try JSONEncoder().encode(countries)
        let model = makeModel { request in
            XCTAssertEqual(request.url?.lastPathComponent, "countries.json")
            return data
        }

        await model.retrieveCountries()

        XCTAssertEqual(model.countries.compactMap { $0.name?.common }, ["Canada", "Japan"])
        XCTAssertTrue(model.countries.contains(try XCTUnwrap(model.current)))
        XCTAssertNil(model.loadingError)
    }

    func testLoadingFailureKeepsSelectionAndRetryClearsError() async throws {
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
        XCTAssertNotNil(model.loadingError)
        XCTAssertEqual(model.countries, [canada])
        XCTAssertEqual(model.current, canada)

        await model.retrieveCountries()
        XCTAssertNil(model.loadingError)
        XCTAssertEqual(model.current?.cca2, "JP")
    }

    func testLoadsAndPersistsInjectedPreferences() async throws {
        let passport = try country("Sweden", "SE", "SWE", currencies: ["SEK"])
        let preferences = MemoryPreferences(nationality: passport, layers: [.earthAtNight: true, .cables: true])
        let model = makeModel(preferences: preferences)

        XCTAssertEqual(model.nationality, passport)
        XCTAssertEqual(model.homeCurrency, "SEK")
        XCTAssertTrue(model.showsEarthAtNight)
        XCTAssertTrue(model.showsCables)
        XCTAssertFalse(model.showsFlights)
        XCTAssertFalse(model.showsHazards)
        XCTAssertFalse(model.showsPowerGrid)
        XCTAssertFalse(model.showsVIIRSImagery)
        XCTAssertFalse(model.showsAurora)

        model.showsEarthAtNight = false
        model.showsPowerGrid = true
        model.showsVIIRSImagery = true
        model.showsAurora = true
        model.showsCables = false
        model.nationality = nil

        let reopened = makeModel(preferences: preferences)
        XCTAssertNil(reopened.nationality)
        XCTAssertFalse(reopened.showsEarthAtNight)
        XCTAssertFalse(reopened.showsCables)
        XCTAssertTrue(reopened.showsPowerGrid)
        XCTAssertTrue(reopened.showsVIIRSImagery)
        XCTAssertTrue(reopened.showsAurora)
    }

    func testDefaultsStorePreservesLegacyNightSettingsAndPassportFormat() async throws {
        let suite = "TellusTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let passport = try country("Sweden", "SE", "SWE")
        defaults.set(try JSONEncoder().encode(passport), forKey: "nationality")
        defaults.set(true, forKey: "showsNightLights")
        let preferences = UserDefaultsMapPreferencesStore(defaults: defaults)
        let model = makeModel(preferences: preferences)

        XCTAssertEqual(model.nationality?.cca2, "SE")
        XCTAssertTrue(model.showsEarthAtNight)
        XCTAssertTrue(model.showsFlights)
        XCTAssertTrue(model.showsHazards)
        XCTAssertFalse(model.showsCables)
        XCTAssertFalse(model.showsAurora)

        model.showsEarthAtNight = false
        model.nationality = nil

        XCTAssertNil(defaults.data(forKey: "nationality"))
        XCTAssertFalse(makeModel(preferences: preferences).showsEarthAtNight)
    }

    func testAuroraForecastUsesValidTimeAndProjectsBothHemispheres() async throws {
        let model = makeModel { request in
            XCTAssertEqual(request.url?.absoluteString, "https://services.swpc.noaa.gov/json/ovation_aurora_latest.json")
            return Data("""
                {"Observation Time":"2026-11-06T23:36:00Z","Forecast Time":"2026-11-07T00:41:00Z",
                 "coordinates":[[350,65,12],[349,65,13],[45,-60,28],[180,70,60],[0,0,0],[0,90,90]]}
                """.utf8)
        }

        let overlay = try await model.loadAuroraForecast()

        XCTAssertEqual(overlay.validAt, try Date("2026-11-07T00:41:00Z", strategy: .iso8601))
        XCTAssertFalse(overlay.isOlder(at: overlay.validAt.addingTimeInterval(29 * 60)))
        XCTAssertTrue(overlay.isOlder(at: overlay.validAt.addingTimeInterval(30 * 60)))
        XCTAssertEqual(overlay.bands.count, 3)
        let green = try XCTUnwrap(overlay.bands[.green]?.first)
        XCTAssertEqual(overlay.bands[.green]?.count, 1)
        XCTAssertTrue(green.contains(MKMapPoint(CLLocationCoordinate2D(latitude: 65, longitude: -10))))
        XCTAssertTrue(green.contains(MKMapPoint(CLLocationCoordinate2D(latitude: 65, longitude: -11))))
        let teal = try XCTUnwrap(overlay.bands[.teal]?.first)
        XCTAssertTrue(teal.contains(MKMapPoint(CLLocationCoordinate2D(latitude: -60, longitude: 45))))
        let dateLine = try XCTUnwrap(overlay.bands[.amber]?.first)
        XCTAssertLessThan(dateLine.minX, 0)
        XCTAssertGreaterThan(dateLine.maxX, 0)
    }

    func testAuroraForecastRejectsInvalidGridAndKeepsValidZeroGrid() throws {
        let date = Date.now
        XCTAssertThrowsError(try AuroraOverlay(validAt: date, coordinates: []))
        XCTAssertThrowsError(try AuroraOverlay(validAt: date, coordinates: [[0, 0]]))
        XCTAssertThrowsError(try AuroraOverlay(validAt: date, coordinates: [[360, 0, 10]]))
        XCTAssertTrue(try AuroraOverlay(validAt: date, coordinates: [[0, 0, 0]]).bands.isEmpty)
    }

    func testEurostatPriceComparisonUsesLatestSharedYearAndKeepsMissingCategories() async throws {
        let model = makeModel { request in
            XCTAssertEqual(request.url?.lastPathComponent, "prc_ppp_ind_1")
            let query = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
            XCTAssertTrue(query.contains(URLQueryItem(name: "indic_ppp", value: "PLI_EU27_2020")))
            XCTAssertEqual(Set(query.filter { $0.name == "ppp_cat18" }.compactMap(\.value)),
                           ["E011", "A0101", "A0104", "A0107", "A0111"])
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
        let greece = try XCTUnwrap(prices.comparison(for: "GR", against: "SE"))
        XCTAssertEqual(greece.year, 2024)
        XCTAssertEqual(try XCTUnwrap(greece.changes[.overall]), -0.25, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(greece.changes[.groceries]), 0.10, accuracy: 0.0001)
        XCTAssertNil(greece.changes[.transport])
        XCTAssertEqual(prices.referenceAreas(for: "GR").map(\.id), ["EU27_2020", "SE"])

        let sweden = try XCTUnwrap(prices.comparison(for: "SE", against: EurostatPriceLevels.euAverageCode))
        XCTAssertEqual(sweden.year, 2025)
        XCTAssertEqual(try XCTUnwrap(sweden.changes[.overall]), 0.21, accuracy: 0.0001)
        XCTAssertEqual(prices.comparison(for: "GB", against: EurostatPriceLevels.euAverageCode)?.year, 2025)
        XCTAssertNil(prices.comparison(for: "CA", against: EurostatPriceLevels.euAverageCode))
    }

    func testPassportRefreshPublishesVisaAndOnlyDestinationCurrencies() async throws {
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

        XCTAssertEqual(model.admissoryStatus?.status, "visa-free")
        XCTAssertEqual(model.admissoryStatus?.dur, "90")
        XCTAssertEqual(model.exchangeRates, [
            ExchangeRate(home: "SEK", destination: "EUR", rate: 0.09, date: "2026-11-01"),
        ])
    }

    func testLateRateFailureDoesNotClearNewPassportRates() async throws {
        let requestedSwedishRates = expectation(description: "The Swedish rate request is in flight")
        let release = AsyncStream<Void>.makeStream()
        let model = makeModel { request in
            switch request.url?.lastPathComponent {
            case "sek.json":
                if request.url?.host == "latest.currency-api.pages.dev" {
                    requestedSwedishRates.fulfill()
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

        await fulfillment(of: [requestedSwedishRates], timeout: 5)
        model.nationality = nextPassport
        await model.refreshPassportInformation()
        release.continuation.finish()
        await olderRefresh.value

        XCTAssertEqual(model.exchangeRates, [
            ExchangeRate(home: "USD", destination: "EUR", rate: 0.86, date: "2026-11-01"),
        ])
    }

    func testCountryWithoutBorderUsesAreaBasedRegion() async throws {
        let model = makeModel()
        model.current = try country("Test Island", "ZZ", "ZZZ")

        await model.refreshDestination()

        XCTAssertNil(model.selectedBorder)
        XCTAssertEqual(model.region.center.latitude, 12)
        XCTAssertEqual(model.region.center.longitude, 34)
        XCTAssertEqual(model.region.span.latitudeDelta, 1)
        XCTAssertEqual(model.region.span.longitudeDelta, 2)
    }

    func testFlightPollingPublishesBothFeedsAndDisablingClearsThem() async throws {
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

        let publishedFlights = expectation(description: "Flight annotations were published")
        withObservationTracking {
            _ = model.flightAnnotations
        } onChange: {
            publishedFlights.fulfill()
        }
        model.startUpdatingFlightData()
        await fulfillment(of: [publishedFlights], timeout: 5)

        XCTAssertEqual(Set(model.flightAnnotations.map(\.id)), ["abc123", "def456"])
        XCTAssertEqual(model.totalFlightCount, 2)
        XCTAssertEqual(model.flight(for: "ABC123")?.source, .openSky)
        XCTAssertEqual(model.flight(for: "def456")?.source, .adsbLolMilitary)

        model.selectedFlight = try XCTUnwrap(model.flightAnnotations.first)
        model.showsFlights = false

        XCTAssertFalse(preferences[.flights])
        XCTAssertNil(model.selectedFlight)
        XCTAssertTrue(model.flightAnnotations.isEmpty)
        XCTAssertNil(model.flight(for: "abc123"))
        XCTAssertEqual(model.totalFlightCount, 0)
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
