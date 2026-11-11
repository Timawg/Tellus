//
//  DisasterAlertService.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2026-11-04.
//

import Foundation

protocol DisasterAlertServiceProtocol: Service {
    /// Current orange and red alerts affecting the country (ISO alpha-2 code).
    func getAlerts(countryCode: String) async throws -> [DisasterAlert]
}

/// Disaster alerts from GDACS, which is free and needs no API key. One list
/// covers every country, so it's fetched once and kept for 30 minutes.
actor DisasterAlertService: DisasterAlertServiceProtocol {

    let networkService: NetworkServiceProtocol
    let requestFactory: URLRequestFactory
    private var cache: (fetched: Date, alerts: [DisasterAlert])?
    private static let lifetime: TimeInterval = 30 * 60

    init(networkService: NetworkServiceProtocol, requestFactory: URLRequestFactory = .default) {
        self.networkService = networkService
        self.requestFactory = requestFactory
    }

    nonisolated let rootURL: String = "https://www.gdacs.org/gdacsapi/api"

    enum DisasterAlertEndpoint: Endpoint {
        /// Orange and red events active in the window.
        case events(from: Date, to: Date)

        var path: String {
            "/events/geteventlist/SEARCH"
        }

        var httpMethod: HTTPMethod {
            return .get
        }

        var queryItems: [URLQueryItem]? {
            switch self {
            case .events(let from, let to):
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(identifier: "UTC")
                formatter.dateFormat = "yyyy-MM-dd"
                return [
                    .init(name: "alertlevel", value: "Orange;Red"),
                    .init(name: "fromdate", value: formatter.string(from: from)),
                    .init(name: "todate", value: formatter.string(from: to)),
                ]
            }
        }

        var cachePolicy: URLRequest.CachePolicy {
            .reloadIgnoringLocalCacheData
        }
    }

    func getAlerts(countryCode: String) async throws -> [DisasterAlert] {
        let code = countryCode.uppercased()
        return try await allAlerts().filter { $0.countryCodes.contains(code) }
    }

    private func allAlerts() async throws -> [DisasterAlert] {
        if let cache, Date().timeIntervalSince(cache.fetched) < Self.lifetime {
            return cache.alerts
        }
        let now = Date()
        let endpoint = DisasterAlertEndpoint.events(from: now.addingTimeInterval(-30 * 24 * 60 * 60), to: now)
        let request = try requestFactory.createURLRequest(root: rootURL, endpoint: endpoint)
        let list: GDACSEventList = try await networkService.send(request: request)
        let alerts = list.currentAlerts
        cache = (now, alerts)
        return alerts
    }
}
