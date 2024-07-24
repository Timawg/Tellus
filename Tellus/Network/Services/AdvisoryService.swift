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
    let requestFactory: URLRequestFactory
    
    init(networkService: NetworkServiceProtocol, requestFactory: URLRequestFactory = .default) {
        self.networkService = networkService
        self.requestFactory = requestFactory
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
            return .get
        }
    }
    
    func getAdvisoryStatus(destination: String) async throws -> AdvisoryStatus {
        let endpoint = AdvisoryEndpoint.advisoryStatus(destination: destination)
        let request = try requestFactory.createURLRequest(root: rootURL, endpoint: endpoint, queryItems: nil, cachePolicy: .reloadRevalidatingCacheData)
       return try await networkService.send(request: request)
    }
}

