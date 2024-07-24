//
//  HTTPError.swift
//  Pokedex
//
//  Created by Tim Gunnarsson on 2024-07-21.
//

import Foundation

enum HTTPError: Error {
    case invalidStatus
    case invalidResponse
    case invalidRequest
}
