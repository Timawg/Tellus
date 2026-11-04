//
//  HTTPError.swift
//  Pokedex
//
//  Created by Tim Gunnarsson on 2024-07-21.
//

import Foundation

enum HTTPError: Error {
    case invalidStatus(code: Int, data: Data)
    /// 429 Too Many Requests. `retryAfter` is how many seconds the server asked
    /// us to wait, if it said.
    case rateLimited(retryAfter: TimeInterval?)
    case invalidResponse
    case invalidRequest
}

extension HTTPError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidStatus(let code, _):
            "Request failed with status \(code) (\(HTTPURLResponse.localizedString(forStatusCode: code)))."
        case .rateLimited(let retryAfter):
            retryAfter.map { "Too many requests. Try again in \(Int($0.rounded(.up))) seconds." } ?? "Too many requests."
        case .invalidResponse:
            "The server returned an invalid response."
        case .invalidRequest:
            "The request could not be created."
        }
    }
}
