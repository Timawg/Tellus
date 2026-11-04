//
//  Endpoint.swift
//  Pokedex
//
//  Created by Tim Gunnarsson on 2024-07-21.
//

import Foundation

protocol Endpoint {
    var path: String { get }
    var httpMethod: HTTPMethod { get }
    var queryItems: [URLQueryItem]? { get }
    var cachePolicy: URLRequest.CachePolicy { get }
}

extension Endpoint {

    var queryItems: [URLQueryItem]? {
        return nil
    }

    /// Defaults to honouring the server's cache headers.
    var cachePolicy: URLRequest.CachePolicy {
        return .useProtocolCachePolicy
    }
}
