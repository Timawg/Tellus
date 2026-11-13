//
//  InternetOutageService.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2026-11-04.
//

import Foundation

protocol InternetOutageServiceProtocol: Service {
    /// Corroborated outages in the country (ISO alpha-2) over the last week.
    func getOutages(countryCode: String) async throws -> [InternetOutage]
}

/// Internet outages from IODA (Georgia Tech), which is free and needs no key.
/// Kept for 15 minutes per country.
actor InternetOutageService: InternetOutageServiceProtocol {

    let networkService: NetworkServiceProtocol
    let requestFactory: URLRequestFactory
    private var cache: [String: (fetched: Date, outages: [InternetOutage])] = [:]
    private static let lifetime: TimeInterval = 15 * 60

    init(networkService: NetworkServiceProtocol, requestFactory: URLRequestFactory = .default) {
        self.networkService = networkService
        self.requestFactory = requestFactory
    }

    nonisolated let rootURL: String = "https://api.ioda.inetintel.cc.gatech.edu/v2"

    enum OutageEndpoint: Endpoint {
        case events(countryCode: String, from: Date, until: Date)

        var path: String {
            "/outages/events"
        }

        var httpMethod: HTTPMethod {
            return .get
        }

        var queryItems: [URLQueryItem]? {
            switch self {
            case .events(let code, let from, let until):
                [
                    .init(name: "entityType", value: "country"),
                    .init(name: "entityCode", value: code),
                    .init(name: "from", value: String(Int(from.timeIntervalSince1970))),
                    .init(name: "until", value: String(Int(until.timeIntervalSince1970))),
                    .init(name: "limit", value: "200"),
                ]
            }
        }

        var cachePolicy: URLRequest.CachePolicy {
            .reloadIgnoringLocalCacheData
        }
    }

    func getOutages(countryCode: String) async throws -> [InternetOutage] {
        let code = countryCode.uppercased()
        guard code.count == 2, code.allSatisfy({ $0.isASCII && $0.isLetter }) else { return [] }
        if let cached = cache[code], Date().timeIntervalSince(cached.fetched) < Self.lifetime {
            return cached.outages
        }
        let now = Date()
        let endpoint = OutageEndpoint.events(countryCode: code, from: now.addingTimeInterval(-7 * 24 * 60 * 60), until: now)
        let request = try requestFactory.createURLRequest(root: rootURL, endpoint: endpoint)
        let list: IODAEventList = try await networkService.send(request: request)
        let outages = list.corroboratedOutages(until: now)
        cache[code] = (now, outages)
        return outages
    }
}
