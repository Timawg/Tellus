//
//  OpenSkyService.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2024-07-24.
//

import Foundation

struct CoordinateSpan {
    let minimum: Double
    let maximum: Double
}

protocol OpenSkyServiceProtocol: Service {
    func getAllFlights(latitudeSpan: CoordinateSpan?, longitudeSpan: CoordinateSpan?) async throws -> FlightData
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
        case all(latitude: CoordinateSpan?, longitude: CoordinateSpan?)
        
        var path: String {
            switch self {
            case .all:
                "/states/all"
            }
        }
        
        var httpMethod: HTTPMethod {
            return .get
        }
        
        var queryItems: [URLQueryItem]? {
            switch self {
            case .all(latitude: let latitudeSpan, longitude: let longitudeSpan):
                let items: [URLQueryItem] = {
                    var items = [URLQueryItem]()
                    if let latitudeSpan {
                        items += [.init(name: "lamin", value: "\(latitudeSpan.minimum)"), .init(name: "lamax", value: "\(latitudeSpan.maximum)")]
                    }
                    
                    if let longitudeSpan {
                        items += [.init(name: "lomin", value: "\(longitudeSpan.minimum)"), .init(name: "lomax", value: "\(longitudeSpan.maximum)")]
                    }
                    return items
                }()
                return items
            }
        }
    }
    
    func getAllFlights(latitudeSpan: CoordinateSpan? = nil, longitudeSpan: CoordinateSpan? = nil) async throws -> FlightData {
        let endpoint: OpenSkyEndpoint = .all(latitude: latitudeSpan, longitude: longitudeSpan)
        let request = try requestFactory.createURLRequest(root: rootURL, endpoint: endpoint, queryItems: endpoint.queryItems, cachePolicy: .useProtocolCachePolicy)
        return try await networkService.send(request: request)
    }
}



