//
//  Service.swift
//  Pokedex
//
//  Created by Tim Gunnarsson on 2024-07-21.
//

import Foundation

protocol Service {
    var rootURL: String { get }
    init(networkService: NetworkServiceProtocol, requestFactory: URLRequestFactory)
}

protocol URLRequestFactory {
        
    func createURL(root: String, endpoint: Endpoint) -> URL?

    func createURLRequest(root: String, endpoint: Endpoint, queryItems: [URLQueryItem]?, cachePolicy: URLRequest.CachePolicy) throws -> URLRequest
    
}

extension URLRequestFactory {

    func createURL(root: String, endpoint: Endpoint) -> URL? {
        URL(string: root + endpoint.path)
    }
    
    func createURLRequest(root: String, endpoint: Endpoint, queryItems: [URLQueryItem]? = nil, cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy) throws -> URLRequest {
        guard let url = createURL(root: root, endpoint: endpoint) else {
            throw URLError(.badURL)
        }
        
        return createURLRequest(url: url, method: endpoint.httpMethod, queryItems: queryItems, cachePolicy: cachePolicy)
    }
    
    private func createURLRequest(url: URL, method: HTTPMethod, queryItems: [URLQueryItem]? = nil, cachePolicy: URLRequest.CachePolicy) -> URLRequest {
        var url = url
        if let queryItems {
            url.append(queryItems: queryItems)
        }

        var request = URLRequest(url: url, cachePolicy: cachePolicy)
        request.httpMethod = method.rawValue
        if let body = method.body {
            request.httpBody = try? JSONEncoder().encode(body)
        }
        return request
    }
}

extension URLRequestFactory where Self == DefaultURLRequestFactory {
    static var `default`: DefaultURLRequestFactory {
        return DefaultURLRequestFactory()
    }
}

struct DefaultURLRequestFactory: URLRequestFactory {
        
}
