//
//  AdmissoryService.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2024-07-24.
//

import Foundation

protocol AdmissoryServiceProtocol: Service {
    func getAdmissoryStatus(passport: String, destination: String) async throws -> AdmissoryStatus
}

final class AdmissoryService: AdmissoryServiceProtocol {

    let networkService: NetworkServiceProtocol
    
    init(networkService: NetworkServiceProtocol) {
        self.networkService = networkService
    }
        
    let rootURL: String = "https://rough-sun-2523.fly.dev/api"
    
    enum AdmissoryEndpoint: Endpoint {
        case admissoryStatus(passport: String, destination: String)
        
        var path: String {
            switch self {
            case .admissoryStatus(passport: let passport, destination: let destination):
                "/\(passport)/\(destination)"
            }
        }
        
        var httpMethod: HTTPMethod {
            return .GET
        }
    }
    
    func getAdmissoryStatus(passport: String, destination: String) async throws -> AdmissoryStatus {
        let endpoint = AdmissoryEndpoint.admissoryStatus(passport: passport, destination: destination)
        return try await networkService.send(request: endpoint.createURLRequest(base: rootURL))
    }
}


