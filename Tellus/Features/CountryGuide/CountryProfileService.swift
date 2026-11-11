import Foundation

enum CountryIndicator: String, CaseIterable {
    enum Category: String, CaseIterable {
        case population = "Population"
        case economy = "Economy"
        case geography = "Geography"
        case infrastructure = "Infrastructure"
    }

    case population = "SP.POP.TOTL"
    case gdp = "NY.GDP.MKTP.CD"
    case gdpPerCapita = "NY.GDP.PCAP.CD"
    case surfaceArea = "AG.SRF.TOTL.K2"
    case internetUse = "IT.NET.USER.ZS"
    case electricityAccess = "EG.ELC.ACCS.ZS"

    var title: String {
        switch self {
        case .population: "Total population"
        case .gdp: "GDP"
        case .gdpPerCapita: "GDP per capita"
        case .surfaceArea: "Surface area"
        case .internetUse: "People using the internet"
        case .electricityAccess: "People with electricity access"
        }
    }

    var category: Category {
        switch self {
        case .population: .population
        case .gdp, .gdpPerCapita: .economy
        case .surfaceArea: .geography
        case .internetUse, .electricityAccess: .infrastructure
        }
    }
}

struct CountryIndicatorObservation: Identifiable {
    let indicator: CountryIndicator
    let value: Double
    let year: Int

    var id: CountryIndicator { indicator }
}

protocol CountryProfileServiceProtocol: Service {
    func getProfile(countryCode: String) async throws -> [CountryIndicatorObservation]
    func getHomicideTrend(countryCode: String) async throws -> [AnnualObservation]
}

actor CountryProfileService: CountryProfileServiceProtocol {
    nonisolated let rootURL = "https://api.worldbank.org/v2"
    static let homicideIndicator = "VC.IHR.PSRC.P5"
    private let networkService: NetworkServiceProtocol
    private let requestFactory: URLRequestFactory
    private var cache: [String: [CountryIndicatorObservation]] = [:]
    private var homicideCache: [String: [AnnualObservation]] = [:]
    private var homicideRetryAt: Date?

    init(networkService: NetworkServiceProtocol, requestFactory: URLRequestFactory = .default) {
        self.networkService = networkService
        self.requestFactory = requestFactory
    }

    func getProfile(countryCode: String) async throws -> [CountryIndicatorObservation] {
        guard let code = Self.normalizedCode(countryCode) else { return [] }
        if let cached = cache[code] { return cached }

        let indicators = CountryIndicator.allCases
        let endpoint = IndicatorsEndpoint(countryCode: code, indicators: indicators.map(\.rawValue), periods: 1)
        let response = try await fetch(endpoint)
        let observations = indicators.compactMap { indicator in
            response.annualObservations(indicator: indicator.rawValue)
                .max { $0.year < $1.year }
                .map { CountryIndicatorObservation(indicator: indicator, value: $0.value, year: $0.year) }
        }
        cache[code] = observations
        return observations
    }

    func getHomicideTrend(countryCode: String) async throws -> [AnnualObservation] {
        guard let code = Self.normalizedCode(countryCode) else { return [] }
        if let cached = homicideCache[code] { return cached }
        if let retryAt = homicideRetryAt, retryAt > .now {
            throw HTTPError.rateLimited(retryAfter: retryAt.timeIntervalSinceNow)
        }

        let indicator = Self.homicideIndicator
        let endpoint = IndicatorsEndpoint(countryCode: code, indicators: [indicator], periods: 10)
        let response: IndicatorsResponse
        do {
            response = try await fetch(endpoint)
        } catch HTTPError.rateLimited(let retryAfter) {
            if let retryAfter { homicideRetryAt = .now.addingTimeInterval(retryAfter) }
            throw HTTPError.rateLimited(retryAfter: retryAfter)
        }
        var reportedYears = Set<Int>()
        let trend = response.annualObservations(indicator: indicator)
            .filter { $0.value >= 0 && reportedYears.insert($0.year).inserted }
            .sorted { $0.year < $1.year }
        homicideCache[code] = trend
        return trend
    }

    private static func normalizedCode(_ countryCode: String) -> String? {
        let code = countryCode.uppercased()
        guard code.count == 2, code.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        return code
    }

    private func fetch(_ endpoint: IndicatorsEndpoint) async throws -> IndicatorsResponse {
        let request = try requestFactory.createURLRequest(root: rootURL, endpoint: endpoint)
        let response: IndicatorsResponse = try await networkService.send(request: request)
        try Task.checkCancellation()
        return response
    }

    private struct IndicatorsEndpoint: Endpoint {
        let countryCode: String
        let indicators: [String]
        let periods: Int
        let httpMethod: HTTPMethod = .get

        var path: String {
            "/country/\(countryCode)/indicator/\(indicators.joined(separator: ";"))"
        }

        var queryItems: [URLQueryItem]? {
            [
                .init(name: "source", value: "2"), // World Development Indicators
                .init(name: "format", value: "json"),
                .init(name: "mrnev", value: String(periods)),
                .init(name: "per_page", value: "50"),
            ]
        }
    }

    private struct IndicatorsResponse: Decodable {
        private let rows: [Row]

        init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            let metadata = try container.decode(Metadata.self)
            if let messages = metadata.message {
                // The API returns HTTP 200 with error 120 for unsupported country codes.
                guard messages.first?.id == "120" else { throw HTTPError.invalidResponse }
                rows = []
                return
            }
            guard let total = metadata.total else { throw HTTPError.invalidResponse }
            rows = total == 0 ? [] : try container.decode([Row].self)
        }

        func annualObservations(indicator: String) -> [AnnualObservation] {
            rows.compactMap { row in
                guard row.indicator.id == indicator, let value = row.value, value.isFinite,
                      let year = Int(row.date), year > 0 else { return nil }
                return AnnualObservation(year: year, value: value)
            }
        }

        private struct Metadata: Decodable {
            let total: Int?
            let message: [Identifier]?
        }

        private struct Identifier: Decodable {
            let id: String
        }

        private struct Row: Decodable {
            let indicator: Identifier
            let date: String
            let value: Double?
        }
    }
}
