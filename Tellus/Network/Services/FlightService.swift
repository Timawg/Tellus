//
//  FlightService.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2024-07-24.
//

import Foundation

struct CoordinateSpan: Sendable {
    let minimum: Double
    let maximum: Double

    func contains(_ value: Double) -> Bool {
        (minimum...maximum).contains(value)
    }
}

/// Tracks when a rate-limited API may be called again.
struct RateLimitBackoff {
    private(set) var resumeDate: Date?
    private var consecutiveLimits = 0

    // Used when the server doesn't say how long to wait: 30s, 60s, 120s …
    // capped at 15 minutes.
    private static let baseDelay: TimeInterval = 30
    private static let maxDelay: TimeInterval = 15 * 60

    /// Seconds left before calls are allowed again, or nil if they are allowed now.
    func remainingDelay(at now: Date) -> TimeInterval? {
        guard let resumeDate, resumeDate > now else { return nil }
        return resumeDate.timeIntervalSince(now)
    }

    mutating func recordRateLimit(retryAfter: TimeInterval?, at now: Date) {
        consecutiveLimits += 1
        let fallback = min(Self.baseDelay * pow(2, Double(consecutiveLimits - 1)), Self.maxDelay)
        resumeDate = now.addingTimeInterval(retryAfter ?? fallback)
    }

    mutating func reset() {
        resumeDate = nil
        consecutiveLimits = 0
    }
}

protocol FlightServiceProtocol: Service {
    /// Aircraft OpenSky sees in the area.
    func getFlights(latitudeSpan: CoordinateSpan?, longitudeSpan: CoordinateSpan?) async throws -> [LiveFlight]
    /// Aircraft adsb.lol flags as military, worldwide.
    func getMilitaryFlights() async throws -> [LiveFlight]
}

/// Live aircraft positions from two free feeds: OpenSky for everything in
/// the visible area, and adsb.lol for the aircraft its database flags as
/// military (a few hundred worldwide, about 170 KB, so it's asked at most
/// every 30 seconds).
///
/// OpenSky limits anonymous use with a daily quota and answers 429 with the
/// number of seconds until it resets. While that window is open OpenSky
/// requests throw `HTTPError.rateLimited` without touching the network, so the
/// 15 second flight polling doesn't keep hitting the API; adsb.lol is
/// unaffected. `actor` isolation keeps the back-off and cache safe from
/// overlapping polls.
actor FlightService: FlightServiceProtocol {

    let networkService: NetworkServiceProtocol
    let requestFactory: URLRequestFactory
    private var backoff = RateLimitBackoff()
    private var militaryCache: (fetched: Date, flights: [LiveFlight])?
    private static let militaryInterval: TimeInterval = 30

    init(networkService: NetworkServiceProtocol, requestFactory: URLRequestFactory = .default) {
        self.networkService = networkService
        self.requestFactory = requestFactory
    }

    nonisolated let rootURL: String = "https://opensky-network.org/api"
    nonisolated let militaryRootURL: String = "https://api.adsb.lol"

    enum FlightEndpoint: Endpoint {
        case all(latitude: CoordinateSpan?, longitude: CoordinateSpan?)
        /// adsb.lol, at `militaryRootURL`.
        case military
        
        var path: String {
            switch self {
            case .all:
                "/states/all"
            case .military:
                "/v2/mil"
            }
        }
        
        var httpMethod: HTTPMethod {
            return .get
        }
        
        var queryItems: [URLQueryItem]? {
            switch self {
            case .all(latitude: let latitudeSpan, longitude: let longitudeSpan):
                let items: [URLQueryItem] = {
                    var items = [URLQueryItem]()
                    if let latitudeSpan {
                        items += [.init(name: "lamin", value: "\(latitudeSpan.minimum)"), .init(name: "lamax", value: "\(latitudeSpan.maximum)")]
                    }
                    
                    if let longitudeSpan {
                        items += [.init(name: "lomin", value: "\(longitudeSpan.minimum)"), .init(name: "lomax", value: "\(longitudeSpan.maximum)")]
                    }
                    return items
                }()
                return items
            case .military:
                return nil
            }
        }

        var cachePolicy: URLRequest.CachePolicy {
            switch self {
            case .all: .useProtocolCachePolicy
            case .military: .reloadIgnoringLocalCacheData
            }
        }
    }
    
    func getFlights(latitudeSpan: CoordinateSpan? = nil, longitudeSpan: CoordinateSpan? = nil) async throws -> [LiveFlight] {
        if let remaining = backoff.remainingDelay(at: Date()) {
            throw HTTPError.rateLimited(retryAfter: remaining)
        }
        let endpoint: FlightEndpoint = .all(latitude: latitudeSpan, longitude: longitudeSpan)
        let request = try requestFactory.createURLRequest(root: rootURL, endpoint: endpoint)
        do {
            let flightData: FlightData = try await networkService.send(request: request)
            backoff.reset()
            return flightData.states.compactMap(LiveFlight.init(state:))
        } catch HTTPError.rateLimited(let retryAfter) {
            // Report the wait actually applied, which includes the fallback
            // delay when the server didn't give one.
            let limitedAt = Date()
            backoff.recordRateLimit(retryAfter: retryAfter, at: limitedAt)
            throw HTTPError.rateLimited(retryAfter: backoff.remainingDelay(at: limitedAt))
        }
    }

    func getMilitaryFlights() async throws -> [LiveFlight] {
        if let militaryCache, Date().timeIntervalSince(militaryCache.fetched) < Self.militaryInterval {
            return militaryCache.flights
        }
        let request = try requestFactory.createURLRequest(root: militaryRootURL, endpoint: FlightEndpoint.military)
        let list: ADSBLolAircraftList = try await networkService.send(request: request)
        let flights = list.flights()
        militaryCache = (Date(), flights)
        return flights
    }
}
