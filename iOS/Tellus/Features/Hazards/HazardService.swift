//
//  HazardService.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2026-11-05.
//

import Foundation

protocol HazardServiceProtocol: Service {
    /// Recent earthquakes, current GDACS events and ongoing eruptions worldwide.
    func getHazards() async throws -> [NaturalHazard]
    /// Path and forecast for a GDACS tropical cyclone.
    func getTrack(for cyclone: NaturalHazard) async throws -> CycloneTrack?
}

/// Natural hazards from three free sources that need no key: USGS
/// earthquakes, GDACS cyclones, floods, droughts and wildfires, and the
/// Smithsonian's list of continuing eruptions. Each source that answers is
/// used, so one being down doesn't empty the layer. Kept for 15 minutes.
actor HazardService: HazardServiceProtocol {

    let networkService: NetworkServiceProtocol
    let requestFactory: URLRequestFactory
    private var cache: (fetched: Date, hazards: [NaturalHazard])?
    private var tracks: [String: CycloneTrack?] = [:]
    private static let lifetime: TimeInterval = 15 * 60

    init(networkService: NetworkServiceProtocol, requestFactory: URLRequestFactory = .default) {
        self.networkService = networkService
        self.requestFactory = requestFactory
    }

    nonisolated let rootURL: String = "https://earthquake.usgs.gov/earthquakes/feed/v1.0"
    nonisolated let gdacsRootURL: String = "https://www.gdacs.org/gdacsapi/api"
    nonisolated let smithsonianRootURL: String = "https://webservices.volcano.si.edu/geoserver/GVP-VOTW"

    enum HazardEndpoint: Endpoint {
        /// Magnitude 4.5 and up, past 7 days.
        case earthquakes
        /// GDACS events of the given types and alert levels in the window.
        case gdacsEvents(types: String, levels: String, from: Date, to: Date)
        /// Track and forecast cone for one cyclone episode.
        case gdacsGeometry(eventID: Int, episodeID: Int)
        case continuingEruptions

        var path: String {
            switch self {
            case .earthquakes: "/summary/4.5_week.geojson"
            case .gdacsEvents: "/events/geteventlist/SEARCH"
            case .gdacsGeometry: "/polygons/getgeometry"
            case .continuingEruptions: "/ows"
            }
        }

        var httpMethod: HTTPMethod {
            return .get
        }

        var queryItems: [URLQueryItem]? {
            switch self {
            case .earthquakes:
                return nil
            case .gdacsEvents(let types, let levels, let from, let to):
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(identifier: "UTC")
                formatter.dateFormat = "yyyy-MM-dd"
                return [
                    .init(name: "eventlist", value: types),
                    .init(name: "alertlevel", value: levels),
                    .init(name: "fromdate", value: formatter.string(from: from)),
                    .init(name: "todate", value: formatter.string(from: to)),
                ]
            case .gdacsGeometry(let eventID, let episodeID):
                return [
                    .init(name: "eventtype", value: "TC"),
                    .init(name: "eventid", value: String(eventID)),
                    .init(name: "episodeid", value: String(episodeID)),
                ]
            case .continuingEruptions:
                return [
                    .init(name: "service", value: "WFS"),
                    .init(name: "version", value: "2.0.0"),
                    .init(name: "request", value: "GetFeature"),
                    .init(name: "typeName", value: "GVP-VOTW:E3WebApp_Eruptions1960"),
                    .init(name: "outputFormat", value: "application/json"),
                    .init(name: "CQL_FILTER", value: "ContinuingEruption='True'"),
                ]
            }
        }

        var cachePolicy: URLRequest.CachePolicy {
            switch self {
            case .earthquakes, .gdacsEvents: .reloadIgnoringLocalCacheData
            case .gdacsGeometry, .continuingEruptions: .useProtocolCachePolicy
            }
        }
    }

    func getHazards() async throws -> [NaturalHazard] {
        if let cache, Date().timeIntervalSince(cache.fetched) < Self.lifetime {
            return cache.hazards
        }
        let now = Date()
        let monthAgo = now.addingTimeInterval(-30 * 24 * 60 * 60)

        async let quakes: USGSEarthquakeFeed? = fetch(.earthquakes, root: rootURL)
        // GDACS lists at most 100 events per request, and there are many
        // small (green) wildfires, so those are left out: fires only show
        // at orange or red. The same goes for droughts, which cover whole
        // regions for months.
        async let events: GDACSEventList? = fetch(
            .gdacsEvents(types: "TC;FL;VO", levels: "Green;Orange;Red", from: monthAgo, to: now),
            root: gdacsRootURL
        )
        async let alerts: GDACSEventList? = fetch(
            .gdacsEvents(types: "WF;DR", levels: "Orange;Red", from: monthAgo, to: now),
            root: gdacsRootURL
        )
        async let eruptions: GVPEruptionFeed? = fetch(.continuingEruptions, root: smithsonianRootURL)

        let (quakeFeed, eventList, alertList, eruptionFeed) = await (quakes, events, alerts, eruptions)
        try Task.checkCancellation()
        guard quakeFeed != nil || eventList != nil || eruptionFeed != nil else {
            throw HTTPError.invalidResponse
        }
        let hazards = ((quakeFeed?.hazards ?? [])
            + (eruptionFeed?.hazards ?? [])
            + (eventList?.hazards ?? [])
            + (alertList?.hazards ?? []))
            .withoutDuplicateVolcanoes()
        cache = (now, hazards)
        return hazards
    }

    func getTrack(for cyclone: NaturalHazard) async throws -> CycloneTrack? {
        guard cyclone.kind == .cyclone, let episode = cyclone.gdacsEpisode else { return nil }
        let key = "\(cyclone.id)-\(episode.episodeID)"
        if let cached = tracks[key] { return cached }
        let geometry: GDACSEventGeometry? = await fetch(
            .gdacsGeometry(eventID: episode.eventID, episodeID: episode.episodeID),
            root: gdacsRootURL
        )
        try Task.checkCancellation()
        let track = geometry?.track(for: cyclone)
        // `updateValue` so a cyclone without a track is remembered too.
        tracks.updateValue(track, forKey: key)
        return track
    }

    /// Nil when the request fails. GDACS answers an empty search with
    /// 204 No Content, which is an empty list rather than an error.
    private func fetch<T: Decodable>(_ endpoint: HazardEndpoint, root: String) async -> T? {
        guard let request = try? requestFactory.createURLRequest(root: root, endpoint: endpoint),
              let data = try? await networkService.send(request: request) else { return nil }
        if data.isEmpty, let empty = try? JSONDecoder().decode(T.self, from: Data(#"{"features":[]}"#.utf8)) {
            return empty
        }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
