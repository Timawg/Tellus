//
//  SubmarineCables.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2026-11-05.
//

import Foundation
import CoreLocation

/// An undersea cable's route, from TeleGeography's Submarine Cable Map.
struct SubmarineCable: Identifiable, Equatable {
    let id: String
    let name: String
    /// TeleGeography's colour for the cable, e.g. "#939597".
    let colorHex: String
    /// The route, split where it branches or crosses the 180° meridian.
    let lines: [[CLLocationCoordinate2D]]

    static func == (lhs: SubmarineCable, rhs: SubmarineCable) -> Bool {
        lhs.id == rhs.id
    }
}

/// A place where cables come ashore, e.g. "Cork, Ireland".
struct CableLandingPoint: Identifiable, Equatable {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D

    static func == (lhs: CableLandingPoint, rhs: CableLandingPoint) -> Bool {
        lhs.id == rhs.id
    }
}

/// Details shown when a cable is tapped.
struct CableDetails: Decodable, Equatable {
    struct LandingPoint: Decodable, Equatable, Identifiable {
        let id: String
        let name: String
        let country: String?
    }

    let id: String
    let name: String
    let length: String?
    let owners: String?
    let suppliers: String?
    let rfsYear: Int?
    let isPlanned: Bool?
    let url: String?
    let landingPoints: [LandingPoint]

    enum CodingKeys: String, CodingKey {
        case id, name, length, owners, suppliers, url
        case rfsYear = "rfs_year"
        case isPlanned = "is_planned"
        case landingPoints = "landing_points"
    }

    /// The cable's page on submarinecablemap.com.
    var mapURL: URL? {
        URL(string: "https://www.submarinecablemap.com/submarine-cable/\(id)")
    }
}

// MARK: - GeoJSON

/// The cable and landing point files are GeoJSON feature collections.
struct CableGeoJSON: Decodable {

    struct Feature: Decodable {
        struct Properties: Decodable {
            let id: String
            let name: String
            let color: String?
        }

        /// `[[[lon, lat]]]` for a MultiLineString, `[lon, lat]` for a Point.
        enum Coordinates: Decodable {
            case point([Double])
            case multiLine([[[Double]]])

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let lines = try? container.decode([[[Double]]].self) {
                    self = .multiLine(lines)
                } else {
                    self = .point(try container.decode([Double].self))
                }
            }
        }

        struct Geometry: Decodable {
            let coordinates: Coordinates
        }

        let properties: Properties
        let geometry: Geometry
    }

    let features: [Feature]

    private static func coordinate(_ pair: [Double]) -> CLLocationCoordinate2D? {
        guard pair.count >= 2 else { return nil }
        return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
    }

    /// One cable per id; a cable can be split over several features.
    var cables: [SubmarineCable] {
        var order: [String] = []
        var byID: [String: (name: String, color: String, lines: [[CLLocationCoordinate2D]])] = [:]
        for feature in features {
            guard case .multiLine(let lines) = feature.geometry.coordinates else { continue }
            let coordinates = lines.map { $0.compactMap(Self.coordinate) }.filter { $0.count >= 2 }
            let id = feature.properties.id
            if byID[id] == nil {
                order.append(id)
                byID[id] = (feature.properties.name, feature.properties.color ?? "#939597", [])
            }
            byID[id]?.lines += coordinates
        }
        return order.compactMap { id in
            byID[id].map { SubmarineCable(id: id, name: $0.name, colorHex: $0.color, lines: $0.lines) }
        }
    }

    var landingPoints: [CableLandingPoint] {
        features.compactMap { feature in
            guard case .point(let pair) = feature.geometry.coordinates,
                  let coordinate = Self.coordinate(pair) else { return nil }
            return CableLandingPoint(id: feature.properties.id, name: feature.properties.name, coordinate: coordinate)
        }
    }
}
