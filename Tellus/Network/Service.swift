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

    func createURLRequest(root: String, endpoint: Endpoint) throws -> URLRequest

}

extension URLRequestFactory {

    func createURL(root: String, endpoint: Endpoint) -> URL? {
        URL(string: root + endpoint.path)
    }

    /// Builds a request from everything the endpoint describes: path, method,
    /// query items and cache policy.
    func createURLRequest(root: String, endpoint: Endpoint) throws -> URLRequest {
        guard var url = createURL(root: root, endpoint: endpoint) else {
            throw URLError(.badURL)
        }
        if let queryItems = endpoint.queryItems, !queryItems.isEmpty {
            url.append(queryItems: queryItems)
        }

        var request = URLRequest(url: url, cachePolicy: endpoint.cachePolicy)
        request.httpMethod = endpoint.httpMethod.rawValue
        if let body = endpoint.httpMethod.body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
