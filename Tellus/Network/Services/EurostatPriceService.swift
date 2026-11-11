import Foundation

struct EurostatPriceLevels: Sendable {
    static let euAverageCode = "EU27_2020"
    static let sourceURL = URL(string: "https://ec.europa.eu/eurostat/databrowser/view/prc_ppp_ind_1/default/table?lang=en")!

    enum Category: String, CaseIterable, Sendable {
        case overall = "E011"
        case groceries = "A0101"
        case housing = "A0104"
        case transport = "A0107"
        case restaurants = "A0111"

        var title: String {
            switch self {
            case .overall: "Overall household prices"
            case .groceries: "Food and non-alcoholic drinks"
            case .housing: "Housing and utilities"
            case .transport: "Transport"
            case .restaurants: "Restaurants and accommodation"
            }
        }
    }

    struct Area: Identifiable, Sendable {
        let id: String
        let name: String
        fileprivate let prices: [Int: [Category: Double]]
    }

    struct Comparison: Sendable {
        let year: Int
        let changes: [Category: Double]
    }

    fileprivate let areas: [String: Area]
    let accessedAt: Date
    let isStale: Bool

    func referenceAreas(for countryCode: String) -> [Area] {
        let code = Self.eurostatCode(for: countryCode)
        guard let country = areas[code] else { return [] }
        return areas.values.filter { area in
            area.id != code && area.prices.keys.contains { country.prices[$0] != nil }
        }.sorted { lhs, rhs in
            if lhs.id == Self.euAverageCode { return rhs.id != Self.euAverageCode }
            if rhs.id == Self.euAverageCode { return false }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    func comparison(for countryCode: String, against referenceCode: String) -> Comparison? {
        guard let country = areas[Self.eurostatCode(for: countryCode)], let reference = areas[referenceCode],
              let year = country.prices.keys.filter({ reference.prices[$0] != nil }).max(),
              let prices = country.prices[year], let referencePrices = reference.prices[year] else { return nil }
        let changes: [(Category, Double)] = prices.compactMap { category, price in
            guard let baseline = referencePrices[category] else { return nil }
            return (category, price / baseline - 1)
        }
        return Comparison(year: year, changes: Dictionary(uniqueKeysWithValues: changes))
    }

    private static func eurostatCode(for countryCode: String) -> String {
        switch countryCode.uppercased() {
        case "GR": "EL"
        case "GB": "UK"
        default: countryCode.uppercased()
        }
    }
}

actor EurostatPriceService: Service {
    nonisolated let rootURL = "https://ec.europa.eu/eurostat/api/dissemination/statistics/1.0"
    private let networkService: NetworkServiceProtocol
    private let requestFactory: URLRequestFactory
    private let now: @Sendable () -> Date
    private var cached: EurostatPriceLevels?
    private var refreshTask: Task<EurostatPriceLevels, Error>?

    init(networkService: NetworkServiceProtocol, requestFactory: URLRequestFactory = .default) {
        self.init(networkService: networkService, requestFactory: requestFactory, now: { .now })
    }

    init(
        networkService: NetworkServiceProtocol,
        requestFactory: URLRequestFactory = .default,
        now: @escaping @Sendable () -> Date
    ) {
        self.networkService = networkService
        self.requestFactory = requestFactory
        self.now = now
    }

    func getPriceLevels() async throws -> EurostatPriceLevels {
        try Task.checkCancellation()
        if let cached, now().timeIntervalSince(cached.accessedAt) < 24 * 60 * 60 { return cached }

        // The whole dataset serves every comparison. Let the refresh finish
        // even when one country guide closes while another is waiting.
        let task = refreshTask ?? Task { try await refresh() }
        refreshTask = task
        let result = await task.result
        try Task.checkCancellation()
        return try result.get()
    }

    private func refresh() async throws -> EurostatPriceLevels {
        defer { refreshTask = nil }
        do {
            let request = try requestFactory.createURLRequest(root: rootURL, endpoint: PriceLevelsEndpoint())
            let response: PriceLevelsResponse = try await networkService.send(request: request)
            let prices = try response.priceLevels(accessedAt: now())
            cached = prices
            return prices
        } catch {
            guard let cached else { throw error }
            return EurostatPriceLevels(areas: cached.areas, accessedAt: cached.accessedAt, isStale: true)
        }
    }

    private struct PriceLevelsEndpoint: Endpoint {
        let path = "/data/prc_ppp_ind_1"
        let httpMethod: HTTPMethod = .get

        var queryItems: [URLQueryItem]? {
            [
                .init(name: "lang", value: "en"),
                .init(name: "freq", value: "A"),
                .init(name: "indic_ppp", value: "PLI_EU27_2020"),
            ] + EurostatPriceLevels.Category.allCases.map { .init(name: "ppp_cat18", value: $0.rawValue) }
        }
    }

    private struct PriceLevelsResponse: Decodable {
        struct Dimension: Decodable {
            struct Category: Decodable {
                let index: [String: Int]
                let label: [String: String]?
            }

            let category: Category
        }

        let id: [String]
        let size: [Int]
        let dimension: [String: Dimension]
        let value: [String: Double]

        func priceLevels(accessedAt: Date) throws -> EurostatPriceLevels {
            guard id.count == size.count, Set(id) == ["freq", "indic_ppp", "ppp_cat18", "geo", "time"],
                  let geography = dimension["geo"]?.category,
                  let timeIndex = dimension["time"]?.category.index,
                  let categoryIndex = dimension["ppp_cat18"]?.category.index,
                  let annual = dimension["freq"]?.category.index["A"],
                  let priceIndex = dimension["indic_ppp"]?.category.index["PLI_EU27_2020"] else {
                throw HTTPError.invalidResponse
            }

            // JSON-stat flattens the cube with the last dimension varying fastest.
            var strides: [String: Int] = [:]
            var stride = 1
            for (axis, count) in zip(id, size).reversed() {
                let (next, overflow) = stride.multipliedReportingOverflow(by: count)
                guard count > 0, !overflow, strides[axis] == nil else { throw HTTPError.invalidResponse }
                strides[axis] = stride
                stride = next
            }

            func offset(_ axis: String, index: Int?) -> Int? {
                guard let dimensionIndex = id.firstIndex(of: axis), let index,
                      (0..<size[dimensionIndex]).contains(index), let stride = strides[axis] else { return nil }
                return index * stride
            }

            guard let frequency = offset("freq", index: annual), let indicator = offset("indic_ppp", index: priceIndex) else {
                throw HTTPError.invalidResponse
            }
            var areas: [String: EurostatPriceLevels.Area] = [:]
            for (code, index) in geography.index where code.count == 2 || code == EurostatPriceLevels.euAverageCode {
                guard let place = offset("geo", index: index) else { continue }
                var observations: [Int: [EurostatPriceLevels.Category: Double]] = [:]
                for (year, index) in timeIndex {
                    guard let number = Int(year), let time = offset("time", index: index) else { continue }
                    var prices: [EurostatPriceLevels.Category: Double] = [:]
                    for category in EurostatPriceLevels.Category.allCases {
                        guard let group = offset("ppp_cat18", index: categoryIndex[category.rawValue]),
                              let price = value[String(frequency + indicator + place + time + group)],
                              price > 0, price.isFinite else { continue }
                        prices[category] = price
                    }
                    if prices[.overall] != nil { observations[number] = prices }
                }
                guard !observations.isEmpty else { continue }
                let name = code == EurostatPriceLevels.euAverageCode ? "EU average" : geography.label?[code] ?? code
                areas[code] = .init(id: code, name: name, prices: observations)
            }
            guard areas[EurostatPriceLevels.euAverageCode] != nil else { throw HTTPError.invalidResponse }
            return EurostatPriceLevels(areas: areas, accessedAt: accessedAt, isStale: false)
        }
    }
}
