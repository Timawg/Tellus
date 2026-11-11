//
//  CableService.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2026-11-05.
//

import Foundation

protocol CableServiceProtocol: Service {
    /// Every cable route and landing point.
    func getCables() async throws -> (cables: [SubmarineCable], landingPoints: [CableLandingPoint])
    /// Length, owners and landing points for one cable.
    func getDetails(cableID: String) async throws -> CableDetails
}

/// Undersea cables from TeleGeography's Submarine Cable Map, which serves its
/// data without a key. The files change rarely and are sent with a 2 hour
/// max-age and an ETag, so the shared URL cache keeps them between launches
/// and revalidates cheaply.
actor CableService: CableServiceProtocol {

    let networkService: NetworkServiceProtocol
    let requestFactory: URLRequestFactory
    private var cables: (cables: [SubmarineCable], landingPoints: [CableLandingPoint])?
    private var details: [String: CableDetails] = [:]

    init(networkService: NetworkServiceProtocol, requestFactory: URLRequestFactory = .default) {
        self.networkService = networkService
        self.requestFactory = requestFactory
    }

    nonisolated let rootURL: String = "https://www.submarinecablemap.com/api/v3"

    enum CableEndpoint: Endpoint {
        case cableRoutes
        case landingPoints
        case cable(id: String)

        var path: String {
            switch self {
            case .cableRoutes: "/cable/cable-geo.json"
            case .landingPoints: "/landing-point/landing-point-geo.json"
            case .cable(let id): "/cable/\(id).json"
            }
        }

        var httpMethod: HTTPMethod {
            return .get
        }
    }

    func getCables() async throws -> (cables: [SubmarineCable], landingPoints: [CableLandingPoint]) {
        if let cables { return cables }
        async let routes: CableGeoJSON = fetch(.cableRoutes)
        async let points: CableGeoJSON = fetch(.landingPoints)
        let result = try await (cables: routes.cables, landingPoints: points.landingPoints)
        try Task.checkCancellation()
        cables = result
        return result
    }

    func getDetails(cableID: String) async throws -> CableDetails {
        guard !cableID.isEmpty, cableID.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else {
            throw HTTPError.invalidRequest
        }
        if let cached = details[cableID] { return cached }
        let result: CableDetails = try await fetch(.cable(id: cableID))
        try Task.checkCancellation()
        details[cableID] = result
        return result
    }

    private func fetch<T: Decodable>(_ endpoint: CableEndpoint) async throws -> T {
        let request = try requestFactory.createURLRequest(root: rootURL, endpoint: endpoint)
        return try await networkService.send(request: request)
    }
}
