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

    let rootURL: String = "https://restcountries.com/v3.1"
    let networkService: NetworkServiceProtocol
    let requestFactory: URLRequestFactory
    
    init(networkService: NetworkServiceProtocol, requestFactory: URLRequestFactory = .default) {
        self.networkService = networkService
        self.requestFactory = requestFactory
    }

    enum CountriesEndpoint: Endpoint {
        case all
        
        var path: String {
            switch self {
            case .all:
                "/all"
            }
        }
        
        var httpMethod: HTTPMethod {
            return .get
        }
    }
    
    func getAllCountries() async throws -> [Country] {
        let request = try requestFactory.createURLRequest(root: rootURL, endpoint: CountriesEndpoint.all, queryItems: nil, cachePolicy: .returnCacheDataElseLoad)
        return try await networkService.send(request: request)
    }
}



