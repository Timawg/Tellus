//
//  ExchangeRateService.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2026-11-04.
//

import Foundation

protocol ExchangeRateServiceProtocol: Service {
    /// Today's rates from `base` (an ISO 4217 code) to every other currency.
    func getRates(base: String) async throws -> ExchangeRates
}

/// Daily exchange rates for 300+ currencies from fawazahmed0/currency-api,
/// which is free and needs no API key. The Cloudflare mirror revalidates on
/// every request; jsDelivr is the fallback, but it marks files cacheable for
/// a week, so its copy is never read from the local cache. Rates are kept for
/// an hour per base currency.
actor ExchangeRateService: ExchangeRateServiceProtocol {

    let networkService: NetworkServiceProtocol
    let requestFactory: URLRequestFactory
    private var cache: [String: (fetched: Date, rates: ExchangeRates)] = [:]
    private static let lifetime: TimeInterval = 60 * 60

    init(networkService: NetworkServiceProtocol, requestFactory: URLRequestFactory = .default) {
        self.networkService = networkService
        self.requestFactory = requestFactory
    }

    nonisolated let rootURL: String = "https://latest.currency-api.pages.dev/v1"
    nonisolated let fallbackRootURL: String = "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1"

    enum ExchangeRateEndpoint: Endpoint {
        case rates(base: String, fallback: Bool)

        var path: String {
            switch self {
            case .rates(let base, _):
                "/currencies/\(base.lowercased()).json"
            }
        }

        var httpMethod: HTTPMethod {
            return .get
        }

        var cachePolicy: URLRequest.CachePolicy {
            switch self {
            case .rates(_, let fallback):
                fallback ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy
            }
        }
    }

    func getRates(base: String) async throws -> ExchangeRates {
        let key = base.uppercased()
        guard !key.isEmpty, key.allSatisfy({ $0.isASCII && $0.isLetter }) else {
            throw HTTPError.invalidRequest
        }
        if let cached = cache[key], Date().timeIntervalSince(cached.fetched) < Self.lifetime {
            return cached.rates
        }
        let rates: ExchangeRates
        do {
            rates = try await fetch(base: key, fallback: false)
        } catch {
            rates = try await fetch(base: key, fallback: true)
        }
        cache[key] = (Date(), rates)
        return rates
    }

    private func fetch(base: String, fallback: Bool) async throws -> ExchangeRates {
        let request = try requestFactory.createURLRequest(
            root: fallback ? fallbackRootURL : rootURL,
            endpoint: ExchangeRateEndpoint.rates(base: base, fallback: fallback)
        )
        return try await networkService.send(request: request)
    }
}
