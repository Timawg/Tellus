//
//  CountriesService.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2024-07-24.
//

import Foundation

protocol CountriesServiceProtocol: Service {
    func getAllCountries() async throws -> [Country]
}

final class CountriesService: CountriesServiceProtocol {

    let networkService: NetworkServiceProtocol
    
    init(networkService: NetworkServiceProtocol) {
        self.networkService = networkService
    }
        
    let rootURL: String = "https://restcountries.com/v3.1"
    
    enum CountriesEndpoint: Endpoint {
        case all
        
        var path: String {
            switch self {
            case .all:
                "/all"
            }
        }
        
        var httpMethod: HTTPMethod {
            return .GET
        }
    }
    
    func getAllCountries() async throws -> [Country] {
        let endpoint = CountriesEndpoint.all
        return try await networkService.send(request: endpoint.createURLRequest(base: rootURL))
    }
}



