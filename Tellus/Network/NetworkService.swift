//
//  NetworkService.swift
//  Pokedex
//
//  Created by Tim Gunnarsson on 2024-07-19.
//

import Foundation
import Combine

protocol NetworkServiceProtocol {
    func send(request: URLRequest) async throws -> Data
    func send<T: Decodable>(request: URLRequest) async throws -> T
}

final class NetworkService: NetworkServiceProtocol {

    private let session: URLSession
    private let decoder: JSONDecoder
    
    private static var urlCache: URLCache {
        let cacheSizeMemory = 20 * 1024 * 1024 // 20 MB
        let cacheSizeDisk = 100 * 1024 * 1024 // 100 MB
        let cache = URLCache(memoryCapacity: cacheSizeMemory, diskCapacity: cacheSizeDisk, diskPath: "URLCacheDirectory")
        return cache
    }
 
    init(session: URLSession? = nil, decoder: JSONDecoder = .init()) {
        let config = URLSessionConfiguration.default
        config.urlCache = NetworkService.urlCache
        config.requestCachePolicy = .reloadRevalidatingCacheData
        self.session = session ?? URLSession(configuration: config)
        self.decoder = decoder
    }
    
    func send(request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        
        guard let response = response as? HTTPURLResponse else {
            throw HTTPError.invalidResponse
        }
        
        guard (200...299).contains(response.statusCode) else {
            throw HTTPError.invalidStatus
        }
        return data
    }
    
    func send<T: Decodable>(request: URLRequest) async throws -> T {
        let data = try await send(request: request)
        let result = try decoder.decode(T.self, from: data)
        return result
    }
}
