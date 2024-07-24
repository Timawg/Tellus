//
//  HTTPMethod.swift
//  Pokedex
//
//  Created by Tim Gunnarsson on 2024-07-21.
//

import Foundation

enum HTTPMethod {
    case get
    case post(Encodable?)
    case put(Encodable?)
    case patch
    case delete
    case head
    
    var rawValue: String {
        switch self {
        case .get:
            return "GET"
        case .post:
            return "POST"
        case .put:
            return "PUT"
        case .patch:
            return "PATCH"
        case .delete:
            return "DELETE"
        case .head:
            return "HEAD"
        }
    }
    
    var body: Encodable? {
        switch self {
        case .put(let body), .post(let body):
            return body
        default: return nil
        }
    }
}
