//
//  Service.swift
//  Pokedex
//
//  Created by Tim Gunnarsson on 2024-07-21.
//

import Foundation

protocol Service {
    var rootURL: String { get }
    var networkService: NetworkServiceProtocol { get }
}
