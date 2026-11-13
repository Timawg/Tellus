//
//  NetworkService.swift
//  Pokedex
//
//  Created by Tim Gunnarsson on 2024-07-19.
//

import Foundation

protocol NetworkServiceProtocol: Sendable {
    func send(request: URLRequest) async throws -> Data
    func send<T: Decodable>(request: URLRequest) async throws -> T
}

final class NetworkService: NetworkServiceProtocol {

    private let session: URLSession
    private let decoder: JSONDecoder
    
    // Created once and shared, so every session uses the same on-disk store.
    private static let urlCache: URLCache = {
        let cacheSizeMemory = 20 * 1024 * 1024 // 20 MB
        let cacheSizeDisk = 100 * 1024 * 1024 // 100 MB
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("URLCacheDirectory", isDirectory: true)
        return URLCache(memoryCapacity: cacheSizeMemory, diskCapacity: cacheSizeDisk, directory: directory)
    }()

    // Each request sets its own cache policy (see `Endpoint.cachePolicy`), so the
    // session only needs the shared cache.
    private static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.urlCache = urlCache
        return URLSession(configuration: config)
    }

    init(session: URLSession? = nil, decoder: JSONDecoder = .init()) {
        self.session = session ?? Self.makeSession()
        self.decoder = decoder
    }
    
    func send(request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        
        guard let response = response as? HTTPURLResponse else {
            throw HTTPError.invalidResponse
        }
        
        if response.statusCode == 429 {
            throw HTTPError.rateLimited(retryAfter: Self.retryAfter(from: response))
        }

        guard (200...299).contains(response.statusCode) else {
            throw HTTPError.invalidStatus(code: response.statusCode, data: data)
        }
        return data
    }

    /// Seconds the server asked us to wait, from the standard `Retry-After`
    /// header (seconds form) or OpenSky's `X-Rate-Limit-Retry-After-Seconds`.
    private static func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        let value = response.value(forHTTPHeaderField: "Retry-After")
            ?? response.value(forHTTPHeaderField: "X-Rate-Limit-Retry-After-Seconds")
        return value.flatMap { TimeInterval($0.trimmingCharacters(in: .whitespaces)) }
    }
    
    func send<T: Decodable>(request: URLRequest) async throws -> T {
        let data = try await send(request: request)
        let result = try decoder.decode(T.self, from: data)
        return result
    }
}
