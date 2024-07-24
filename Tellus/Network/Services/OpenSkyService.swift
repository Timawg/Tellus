//
//  OpenSkyService.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2024-07-24.
//

import Foundation

protocol OpenSkyServiceProtocol: Service {
    func getAllFlights() async throws -> FlightData
}

final class OpenSkyService: OpenSkyServiceProtocol {

    let networkService: NetworkServiceProtocol
    let requestFactory: URLRequestFactory
    
    init(networkService: NetworkServiceProtocol, requestFactory: URLRequestFactory = .default) {
        self.networkService = networkService
        self.requestFactory = requestFactory
    }
        
    let rootURL: String = "https://opensky-network.org/api"
    
    enum OpenSkyEndpoint: Endpoint {
        case all
        
        var path: String {
            switch self {
            case .all:
                "/states/all"
            }
        }
        
        var httpMethod: HTTPMethod {
            return .get
        }
    }
    
    func getAllFlights() async throws -> FlightData {
        let endpoint: OpenSkyEndpoint = .all
        let request = try requestFactory.createURLRequest(root: rootURL, endpoint: endpoint, queryItems: nil, cachePolicy: .useProtocolCachePolicy)
        return try await networkService.send(request: request)
    }
}



