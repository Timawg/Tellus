//
//  DisasterAlerts.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2026-11-04.
//

import Foundation
import CoreLocation

/// An orange or red alert from GDACS, the UN and EU's Global Disaster Alert
/// and Coordination System.
struct DisasterAlert: Equatable, Identifiable {

    enum Kind: String {
        case cyclone = "TC", earthquake = "EQ", flood = "FL", volcano = "VO"
        case drought = "DR", wildfire = "WF", tsunami = "TS", other

        var title: String {
            switch self {
            case .cyclone: "Tropical cyclone"
            case .earthquake: "Earthquake"
            case .flood: "Flood"
            case .volcano: "Volcano"
            case .drought: "Drought"
            case .wildfire: "Wildfire"
            case .tsunami: "Tsunami"
            case .other: "Disaster"
            }
        }

        var symbolName: String {
            switch self {
            case .cyclone: "hurricane"
            case .earthquake: "waveform.path.ecg"
            case .flood: "water.waves"
            case .volcano: "mountain.2.fill"
            case .drought: "sun.max.trianglebadge.exclamationmark"
            case .wildfire: "flame.fill"
            case .tsunami: "water.waves.and.arrow.trianglehead.up"
            case .other: "exclamationmark.triangle.fill"
            }
        }
    }

    enum Level: String {
        case orange = "Orange", red = "Red"
    }

    let id: String
    let kind: Kind
    let level: Level
    let name: String
    let severity: String?
    let start: Date?
    let end: Date?
    /// ISO 3166-1 alpha-2 codes of the countries affected.
    let countryCodes: Set<String>
    let reportURL: URL?

    /// Droughts last months and cover whole regions, so they're listed in the
    /// guide but don't get a banner on the map card.
    var isUrgent: Bool {
        kind != .drought
    }
}

/// GDACS event list: a GeoJSON feature collection.
struct GDACSEventList: Decodable {

    struct Feature: Decodable {
        let properties: Properties
        let geometry: Geometry?
    }

    /// Events in the list are points: their centre.
    struct Geometry: Decodable {
        let point: CLLocationCoordinate2D?

        enum CodingKeys: String, CodingKey { case coordinates }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let pair = try? container.decode([Double].self, forKey: .coordinates)
            if let pair, pair.count >= 2, (-90...90).contains(pair[1]), (-180...180).contains(pair[0]) {
                point = CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
            } else {
                point = nil
            }
        }
    }

    struct Properties: Decodable {
        struct Country: Decodable {
            let iso2: String?
            let countryname: String?
        }
        struct Severity: Decodable {
            let severitytext: String?
        }
        struct Links: Decodable {
            let report: String?
        }

        let eventtype: String
        let eventid: Int
        let episodeid: Int?
        let name: String?
        let country: String?
        let alertlevel: String
        let iscurrent: FlexibleBool?
        let fromdate: String?
        let todate: String?
        let affectedcountries: [Country]?
        let severitydata: Severity?
        let url: Links?
    }

    /// GDACS sends `"true"` as a string, but may send a real boolean.
    struct FlexibleBool: Decodable {
        let value: Bool
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let bool = try? container.decode(Bool.self) {
                value = bool
            } else {
                value = (try container.decode(String.self)).lowercased() == "true"
            }
        }
    }

    let features: [Feature]

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()

    /// Current orange and red alerts. An event can be listed once per
    /// episode; the latest episode wins.
    var currentAlerts: [DisasterAlert] {
        var seen = Set<String>()
        return features.reversed().compactMap { feature -> DisasterAlert? in
            let p = feature.properties
            guard p.iscurrent?.value != false,
                  let level = DisasterAlert.Level(rawValue: p.alertlevel) else { return nil }
            let id = "\(p.eventtype)-\(p.eventid)"
            guard seen.insert(id).inserted else { return nil }
            return DisasterAlert(
                id: id,
                kind: DisasterAlert.Kind(rawValue: p.eventtype) ?? .other,
                level: level,
                name: p.name ?? DisasterAlert.Kind(rawValue: p.eventtype)?.title ?? "Disaster",
                severity: p.severitydata?.severitytext,
                start: p.fromdate.flatMap(Self.dateFormatter.date(from:)),
                end: p.todate.flatMap(Self.dateFormatter.date(from:)),
                countryCodes: Set((p.affectedcountries ?? []).compactMap { $0.iso2?.uppercased() }),
                reportURL: p.url?.report.flatMap(URL.init(string:))
            )
        }
        .sorted { ($0.level == .red ? 0 : 1, $0.start ?? .distantPast) < ($1.level == .red ? 0 : 1, $1.start ?? .distantPast) }
    }
}
