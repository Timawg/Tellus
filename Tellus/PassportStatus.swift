//
//  PassportStatus.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2023-09-19.
//

import Foundation

import Foundation

// MARK: - Welcome
struct PassportStatus: Codable {
    let passport, destination, dur, status: String
    let category, lastUpdated: String
    let error: Error

    enum CodingKeys: String, CodingKey {
        case passport, destination, dur, status, category
        case lastUpdated = "last_updated"
        case error
    }
}

// MARK: - Error
struct Error: Codable {
    let status: Bool
    let error: String
}
