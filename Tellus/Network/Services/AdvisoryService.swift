//
//  EvolutionService.swift
//  Pokedex
//
//  Created by Tim Gunnarsson on 2024-07-21.
//

import Foundation

protocol AdvisoryServiceProtocol: Service {
    func getAdvisoryStatus(destination: String) async throws -> AdvisoryStatus
}

final class AdvisoryService: AdvisoryServiceProtocol {
    
    let networkService: NetworkServiceProtocol
    
    init(networkService: NetworkServiceProtocol) {
        self.networkService = networkService
    }
        
    let rootURL: String = "https://data.international.gc.ca/travel-voyage"
    
    enum AdvisoryEndpoint: Endpoint {
        case advisoryStatus(destination: String)
        
        var path: String {
            switch self {
            case .advisoryStatus(destination: let destination):
                "/cta-cap-\(destination).json"
            }
        }
        
        var httpMethod: HTTPMethod {
            return .GET
        }
    }
    
    func getAdvisoryStatus(destination: String) async throws -> AdvisoryStatus {
        let endpoint = AdvisoryEndpoint.advisoryStatus(destination: destination)
        return try await networkService.send(request: endpoint.createURLRequest(base: rootURL))
    }
}

