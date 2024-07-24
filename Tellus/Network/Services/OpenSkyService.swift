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
    
    init(networkService: NetworkServiceProtocol) {
        self.networkService = networkService
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
            return .GET
        }
    }
    
    func getAllFlights() async throws -> FlightData {
        let endpoint = OpenSkyEndpoint.all
        return try await networkService.send(request: endpoint.createURLRequest(base: rootURL))
    }
}



