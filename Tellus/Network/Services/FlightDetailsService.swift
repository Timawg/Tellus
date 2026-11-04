//
//  FlightDetailsService.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2026-11-04.
//

import Foundation

protocol FlightDetailsServiceProtocol: Service {
    /// Registration details, or nil if adsbdb doesn't know the aircraft.
    func getAircraft(icao24: String) async throws -> AircraftInfo?
    /// Scheduled route, or nil if adsbdb doesn't know the callsign.
    func getRoute(callsign: String) async throws -> FlightRoute?
}

/// Aircraft and route details from adsbdb.com, a free, community-maintained
/// database that needs no API key. Answers (including "unknown") are cached
/// for the session, since they don't change while a flight is in the air.
actor FlightDetailsService: FlightDetailsServiceProtocol {

    let networkService: NetworkServiceProtocol
    let requestFactory: URLRequestFactory
    private var aircraftCache: [String: AircraftInfo?] = [:]
    private var routeCache: [String: FlightRoute?] = [:]

    init(networkService: NetworkServiceProtocol, requestFactory: URLRequestFactory = .default) {
        self.networkService = networkService
        self.requestFactory = requestFactory
    }

    nonisolated let rootURL: String = "https://api.adsbdb.com/v0"

    enum FlightDetailsEndpoint: Endpoint {
        case aircraft(icao24: String)
        case callsign(String)

        var path: String {
            switch self {
            case .aircraft(let icao24):
                "/aircraft/\(icao24)"
            case .callsign(let callsign):
                "/callsign/\(callsign)"
            }
        }

        var httpMethod: HTTPMethod {
            return .get
        }
    }

    /// adsbdb wraps every answer as `{"response": …}`.
    private struct Response<Body: Decodable>: Decodable {
        let response: Body
    }

    private struct AircraftBody: Decodable {
        let aircraft: AircraftInfo
    }

    private struct RouteBody: Decodable {
        let flightroute: FlightRoute
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    func getAircraft(icao24: String) async throws -> AircraftInfo? {
        let key = icao24.lowercased()
        guard Self.isSafePathComponent(key) else { return nil }
        if let cached = aircraftCache[key] { return cached }
        let body: AircraftBody? = try await fetch(.aircraft(icao24: key))
        // updateValue, because assigning nil would remove the entry instead of
        // remembering that the aircraft is unknown.
        aircraftCache.updateValue(body?.aircraft, forKey: key)
        return body?.aircraft
    }

    func getRoute(callsign: String) async throws -> FlightRoute? {
        let key = callsign.trimmingCharacters(in: .whitespaces).uppercased()
        guard Self.isSafePathComponent(key) else { return nil }
        if let cached = routeCache[key] { return cached }
        let body: RouteBody? = try await fetch(.callsign(key))
        routeCache.updateValue(body?.flightroute, forKey: key)
        return body?.flightroute
    }

    /// The decoded body, or nil when adsbdb answers 404 ("unknown aircraft" /
    /// "unknown callsign").
    private func fetch<Body: Decodable>(_ endpoint: FlightDetailsEndpoint) async throws -> Body? {
        let request = try requestFactory.createURLRequest(root: rootURL, endpoint: endpoint)
        do {
            let data: Data = try await networkService.send(request: request)
            return try Self.decoder.decode(Response<Body>.self, from: data).response
        } catch HTTPError.invalidStatus(code: 404, _) {
            return nil
        }
    }

    private static func isSafePathComponent(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }
}
