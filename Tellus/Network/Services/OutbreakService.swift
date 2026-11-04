//
//  OutbreakService.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2026-11-04.
//

import Foundation

protocol OutbreakServiceProtocol: Service {
    /// WHO's latest Disease Outbreak News reports, newest first.
    func getReports() async throws -> [OutbreakReport]
}

/// WHO Disease Outbreak News, which is free and needs no key. One list covers
/// every country, so it's fetched once and kept for an hour.
actor OutbreakService: OutbreakServiceProtocol {

    let networkService: NetworkServiceProtocol
    let requestFactory: URLRequestFactory
    private var cache: (fetched: Date, reports: [OutbreakReport])?
    private static let lifetime: TimeInterval = 60 * 60

    init(networkService: NetworkServiceProtocol, requestFactory: URLRequestFactory = .default) {
        self.networkService = networkService
        self.requestFactory = requestFactory
    }

    nonisolated let rootURL: String = "https://www.who.int/api"

    enum OutbreakEndpoint: Endpoint {
        case latest

        var path: String {
            "/news/diseaseoutbreaknews"
        }

        var httpMethod: HTTPMethod {
            return .get
        }

        var queryItems: [URLQueryItem]? {
            [
                .init(name: "$orderby", value: "PublicationDate desc"),
                // The API's maximum page size; about two years of reports.
                .init(name: "$top", value: "100"),
                .init(name: "$select", value: "Title,PublicationDate,UrlName,Summary"),
            ]
        }
    }

    func getReports() async throws -> [OutbreakReport] {
        if let cache, Date().timeIntervalSince(cache.fetched) < Self.lifetime {
            return cache.reports
        }
        let request = try requestFactory.createURLRequest(root: rootURL, endpoint: OutbreakEndpoint.latest)
        let list: WHOOutbreakList = try await networkService.send(request: request)
        let reports = list.reports
        cache = (Date(), reports)
        return reports
    }
}
