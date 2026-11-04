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

    // The RestCountries v3.1 "all countries" endpoint has been deprecated and
    // now requires an API key. We instead read the open dataset RestCountries is
    // built from (mledoze/countries), served over the jsDelivr CDN. Same shape,
    // one request, no auth.
    let rootURL: String = "https://cdn.jsdelivr.net/gh/mledoze/countries@master"
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
                "/countries.json"
            }
        }
        
        var httpMethod: HTTPMethod {
            return .get
        }
    }
    
    func getAllCountries() async throws -> [Country] {
        let request = try requestFactory.createURLRequest(root: rootURL, endpoint: CountriesEndpoint.all)
        return try await networkService.send(request: request)
    }
}



