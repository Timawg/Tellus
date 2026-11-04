//
//  OpenSkyService.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2024-07-24.
//

import Foundation

struct CoordinateSpan {
    let minimum: Double
    let maximum: Double
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

protocol OpenSkyServiceProtocol: Service {
    func getAllFlights(latitudeSpan: CoordinateSpan?, longitudeSpan: CoordinateSpan?) async throws -> FlightData
}

/// OpenSky limits anonymous use with a daily quota and answers 429 with the
/// number of seconds until it resets. While that window is open this service
/// throws `HTTPError.rateLimited` without touching the network, so the 15 second
/// flight polling doesn't keep hitting the API. `actor` isolation keeps the
/// back-off state safe from overlapping polls.
actor OpenSkyService: OpenSkyServiceProtocol {

    let networkService: NetworkServiceProtocol
    let requestFactory: URLRequestFactory
    private var backoff = RateLimitBackoff()

    init(networkService: NetworkServiceProtocol, requestFactory: URLRequestFactory = .default) {
        self.networkService = networkService
        self.requestFactory = requestFactory
    }

    nonisolated let rootURL: String = "https://opensky-network.org/api"

    enum OpenSkyEndpoint: Endpoint {
        case all(latitude: CoordinateSpan?, longitude: CoordinateSpan?)
        
        var path: String {
            switch self {
            case .all:
                "/states/all"
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
            }
        }
    }
    
    func getAllFlights(latitudeSpan: CoordinateSpan? = nil, longitudeSpan: CoordinateSpan? = nil) async throws -> FlightData {
        if let remaining = backoff.remainingDelay(at: Date()) {
            throw HTTPError.rateLimited(retryAfter: remaining)
        }
        let endpoint: OpenSkyEndpoint = .all(latitude: latitudeSpan, longitude: longitudeSpan)
        let request = try requestFactory.createURLRequest(root: rootURL, endpoint: endpoint)
        do {
            let flightData: FlightData = try await networkService.send(request: request)
            backoff.reset()
            return flightData
        } catch HTTPError.rateLimited(let retryAfter) {
            // Report the wait actually applied, which includes the fallback
            // delay when the server didn't give one.
            let limitedAt = Date()
            backoff.recordRateLimit(retryAfter: retryAfter, at: limitedAt)
            throw HTTPError.rateLimited(retryAfter: backoff.remainingDelay(at: limitedAt))
        }
    }
}



