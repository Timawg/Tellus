//
//  RecentEventsService.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2026-11-04.
//

import Foundation

protocol RecentEventsServiceProtocol: Service {
    /// Recent events from Wikipedia's "<year> in <country>" article, or nil
    /// if there's no such article.
    func getRecentEvents(for country: Country) async throws -> RecentEvents?
}

/// Recent events from English Wikipedia, which is free and needs no key.
/// Wikimedia asks API clients to identify themselves with a User-Agent that
/// includes a contact URL. Results are kept for 30 minutes per country.
actor RecentEventsService: RecentEventsServiceProtocol {

    let networkService: NetworkServiceProtocol
    let requestFactory: URLRequestFactory
    private var cache: [String: (fetched: Date, events: RecentEvents?)] = [:]
    private static let lifetime: TimeInterval = 30 * 60
    private static let userAgent = "Tellus/1.0 (https://github.com/Timawg/Tellus)"

    /// Countries whose article doesn't follow the usual names.
    private static let titleOverrides = ["TR": "Turkey", "GE": "Georgia (country)"]

    init(networkService: NetworkServiceProtocol, requestFactory: URLRequestFactory = .default) {
        self.networkService = networkService
        self.requestFactory = requestFactory
    }

    nonisolated let rootURL: String = "https://en.wikipedia.org/w"

    enum RecentEventsEndpoint: Endpoint {
        /// Current wikitext of the pages, following redirects.
        case pages(titles: [String])

        var path: String {
            "/api.php"
        }

        var httpMethod: HTTPMethod {
            return .get
        }

        var queryItems: [URLQueryItem]? {
            switch self {
            case .pages(let titles):
                [
                    .init(name: "action", value: "query"),
                    .init(name: "prop", value: "revisions"),
                    .init(name: "rvprop", value: "content"),
                    .init(name: "rvslots", value: "main"),
                    .init(name: "titles", value: titles.joined(separator: "|")),
                    .init(name: "redirects", value: "1"),
                    .init(name: "format", value: "json"),
                    .init(name: "formatversion", value: "2"),
                ]
            }
        }
    }

    private struct QueryResponse: Decodable {
        struct Query: Decodable {
            struct Mapping: Decodable { let from: String; let to: String }
            struct Page: Decodable {
                struct Revision: Decodable {
                    struct Slots: Decodable {
                        struct Main: Decodable { let content: String? }
                        let main: Main
                    }
                    let slots: Slots
                }
                let title: String
                let missing: Bool?
                let revisions: [Revision]?
            }
            let normalized: [Mapping]?
            let redirects: [Mapping]?
            let pages: [Page]
        }
        let query: Query
    }

    func getRecentEvents(for country: Country) async throws -> RecentEvents? {
        let key = country.cca2 ?? country.name?.common ?? ""
        if let cached = cache[key], Date().timeIntervalSince(cached.fetched) < Self.lifetime {
            return cached.events
        }

        let calendar = Calendar.current
        let year = calendar.component(.year, from: Date())
        // Early in the year the new article is still short, so add last year's.
        let years = calendar.component(.month, from: Date()) <= 2 ? [year, year - 1] : [year]
        let candidates = years.map { ($0, Self.candidateTitles(for: country, year: $0)) }

        var request = try requestFactory.createURLRequest(
            root: rootURL,
            endpoint: RecentEventsEndpoint.pages(titles: candidates.flatMap(\.1))
        )
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(Self.userAgent, forHTTPHeaderField: "Api-User-Agent")
        let response: QueryResponse = try await networkService.send(request: request)

        let query = response.query
        let normalized = Dictionary((query.normalized ?? []).map { ($0.from, $0.to) }, uniquingKeysWith: { first, _ in first })
        let redirects = Dictionary((query.redirects ?? []).map { ($0.from, $0.to) }, uniquingKeysWith: { first, _ in first })
        let pages = Dictionary(query.pages.filter { $0.missing != true }.map { ($0.title, $0) }, uniquingKeysWith: { first, _ in first })

        var events: [RecentEvent] = []
        var articleTitle: String?
        for (year, titles) in candidates {
            // The first candidate that exists, after normalising and redirects.
            let page = titles.lazy.compactMap { title -> QueryResponse.Query.Page? in
                let normal = normalized[title] ?? title
                return pages[redirects[normal] ?? normal]
            }.first
            guard let page, let text = page.revisions?.first?.slots.main.content else { continue }
            articleTitle = articleTitle ?? page.title
            events += WikipediaEventsParser.events(fromWikitext: text, year: year)
        }

        let result = articleTitle.map { title in
            RecentEvents(
                events: events.enumerated().map { RecentEvent(id: $0.offset, date: $0.element.date, text: $0.element.text) },
                articleTitle: title
            )
        }
        cache[key] = (Date(), result)
        return result
    }

    /// "2026 in Kenya", "2026 in the Bahamas", "2026 in the Czech Republic"…
    static func candidateTitles(for country: Country, year: Int) -> [String] {
        var names: [String] = []
        if let code = country.cca2, let override = titleOverrides[code] {
            names.append(override)
        }
        for name in [country.name?.common, country.name?.official].compactMap({ $0 }) {
            names += [name, "the \(name)"]
        }
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }.map { "\(year) in \($0)" }
    }
}
