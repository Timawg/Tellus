//
//  FlightData.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2024-07-24.
//

import Foundation

struct FlightData: Codable {
    let time: Int
    let states: [StateVector]

    enum CodingKeys: String, CodingKey {
        case time
        case states
    }
}

struct StateVector: Codable {
    let icao24: String
    let callsign: String?
    let originCountry: String
    let timePosition: Int?
    let lastContact: Int
    let longitude: Float?
    let latitude: Float?
    let baroAltitude: Float?
    let onGround: Bool
    let velocity: Float?
    let trueTrack: Float?
    let verticalRate: Float?
    let sensors: [Int]?
    let geoAltitude: Float?
    let squawk: String?
    let spi: Bool
    let positionSource: Int
    let category: Int?

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        icao24 = try container.decode(String.self)
        callsign = try container.decodeIfPresent(String.self)
        originCountry = try container.decode(String.self)
        timePosition = try container.decodeIfPresent(Int.self)
        lastContact = try container.decode(Int.self)
        longitude = try container.decodeIfPresent(Float.self)
        latitude = try container.decodeIfPresent(Float.self)
        baroAltitude = try container.decodeIfPresent(Float.self)
        onGround = try container.decode(Bool.self)
        velocity = try container.decodeIfPresent(Float.self)
        trueTrack = try container.decodeIfPresent(Float.self)
        verticalRate = try container.decodeIfPresent(Float.self)
        sensors = try container.decodeIfPresent([Int].self)
        geoAltitude = try container.decodeIfPresent(Float.self)
        squawk = try container.decodeIfPresent(String.self)
        spi = try container.decode(Bool.self)
        positionSource = try container.decode(Int.self)
        category = try container.decodeIfPresent(Int.self)
    }
}
