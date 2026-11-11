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
}

actor CountryProfileService: CountryProfileServiceProtocol {
    nonisolated let rootURL = "https://api.worldbank.org/v2"
    private let networkService: NetworkServiceProtocol
    private let requestFactory: URLRequestFactory
    private var cache: [String: [CountryIndicatorObservation]] = [:]

    init(networkService: NetworkServiceProtocol, requestFactory: URLRequestFactory = .default) {
        self.networkService = networkService
        self.requestFactory = requestFactory
    }

    func getProfile(countryCode: String) async throws -> [CountryIndicatorObservation] {
        let code = countryCode.uppercased()
        guard code.count == 2, code.allSatisfy({ $0.isASCII && $0.isLetter }) else { return [] }
        if let cached = cache[code] { return cached }

        let request = try requestFactory.createURLRequest(root: rootURL, endpoint: IndicatorsEndpoint(countryCode: code))
        let response: IndicatorsResponse = try await networkService.send(request: request)
        let observations = CountryIndicator.allCases.compactMap { indicator in
            response.observations
                .filter { $0.indicator == indicator }
                .max { $0.year < $1.year }
        }
        cache[code] = observations
        return observations
    }

    private struct IndicatorsEndpoint: Endpoint {
        let countryCode: String
        let httpMethod: HTTPMethod = .get

        var path: String {
            let indicators = CountryIndicator.allCases.map(\.rawValue).joined(separator: ";")
            return "/country/\(countryCode)/indicator/\(indicators)"
        }

        var queryItems: [URLQueryItem]? {
            [
                .init(name: "source", value: "2"), // World Development Indicators
                .init(name: "format", value: "json"),
                .init(name: "mrnev", value: "1"), // Latest non-empty value for each series
                .init(name: "per_page", value: "50"),
            ]
        }
    }

    private struct IndicatorsResponse: Decodable {
        let observations: [CountryIndicatorObservation]

        init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            let metadata = try container.decode(Metadata.self)
            if let messages = metadata.message {
                // The API returns HTTP 200 with error 120 for unsupported country codes.
                guard messages.first?.id == "120" else { throw HTTPError.invalidResponse }
                observations = []
                return
            }
            guard let total = metadata.total else { throw HTTPError.invalidResponse }
            let rows = total == 0 ? [] : try container.decode([Row].self)
            observations = rows.compactMap { row in
                guard let indicator = CountryIndicator(rawValue: row.indicator.id),
                      let value = row.value, let year = Int(row.date) else { return nil }
                return CountryIndicatorObservation(indicator: indicator, value: value, year: year)
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
