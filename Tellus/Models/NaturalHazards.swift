//
//  NaturalHazards.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2026-11-05.
//

import Foundation
import CoreLocation

/// Something happening in nature right now, drawn on the map's hazards layer:
/// an earthquake from USGS, a cyclone, flood, drought or wildfire from GDACS,
/// or an ongoing volcanic eruption from the Smithsonian.
struct NaturalHazard: Identifiable, Equatable {

    enum Severity: Int, Comparable {
        case minor, moderate, severe

        static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    enum Source: String {
        case usgs = "USGS"
        case gdacs = "GDACS"
        case smithsonian = "Smithsonian Global Volcanism Program"
    }

    let id: String
    let kind: DisasterAlert.Kind
    let name: String
    let coordinate: CLLocationCoordinate2D
    let severity: Severity
    /// When an earthquake struck, or when anything else began.
    let date: Date?
    /// GDACS: the latest update in its report.
    let updated: Date?
    /// Where, e.g. "12 km SSW of Hualien City, Taiwan" or "Brazil, Guyana".
    let place: String?
    /// e.g. "Maximum wind speed of 157 km/h" or "6,306 ha burned".
    let summary: String?
    /// Earthquakes: magnitude and depth in kilometres.
    let magnitude: Double?
    let depth: Double?
    /// Earthquakes: USGS flagged it in an ocean region where a tsunami is possible.
    let mayCauseTsunami: Bool
    /// GDACS alert level or USGS PAGER level, e.g. "Orange".
    let alertLevel: String?
    /// Volcanoes: largest Volcanic Explosivity Index (0–8) of the eruption.
    let explosivity: Int?
    let source: Source
    let url: URL?
    /// GDACS event and episode, for looking up a cyclone's track.
    let gdacsEpisode: (eventID: Int, episodeID: Int)?

    static func == (lhs: NaturalHazard, rhs: NaturalHazard) -> Bool {
        lhs.id == rhs.id
            && lhs.severity == rhs.severity
            && lhs.updated == rhs.updated
            && lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
    }
}

/// A tropical cyclone's path so far and GDACS's forecast for where it goes next.
struct CycloneTrack: Equatable {
    let hazardID: String
    let severity: NaturalHazard.Severity
    /// Short segments; drawn solid.
    let observed: [[CLLocationCoordinate2D]]
    /// Drawn dashed.
    let forecast: [[CLLocationCoordinate2D]]

    static func == (lhs: CycloneTrack, rhs: CycloneTrack) -> Bool {
        lhs.hazardID == rhs.hazardID
            && lhs.severity == rhs.severity
            && lhs.observed.count == rhs.observed.count
            && lhs.forecast.count == rhs.forecast.count
    }
}

private func coordinate(_ pair: [Double]) -> CLLocationCoordinate2D? {
    guard pair.count >= 2, (-90...90).contains(pair[1]), (-180...180).contains(pair[0]) else { return nil }
    return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
}

// MARK: - USGS

/// USGS's GeoJSON summary feed of recent earthquakes.
struct USGSEarthquakeFeed: Decodable {

    struct Feature: Decodable {
        struct Properties: Decodable {
            let mag: Double?
            let place: String?
            /// Milliseconds since 1970.
            let time: Double?
            let updated: Double?
            let url: String?
            let tsunami: Int?
            /// PAGER impact level: green, yellow, orange or red.
            let alert: String?
            let type: String?
        }
        struct Geometry: Decodable {
            /// Longitude, latitude, depth in km.
            let coordinates: [Double]
        }

        let id: String
        let properties: Properties
        let geometry: Geometry?
    }

    let features: [Feature]

    var hazards: [NaturalHazard] {
        features.compactMap { feature in
            let p = feature.properties
            guard p.type == nil || p.type == "earthquake",
                  let magnitude = p.mag,
                  let coordinates = feature.geometry?.coordinates,
                  let location = coordinate(coordinates) else { return nil }
            let pager = p.alert?.lowercased()
            let severity: NaturalHazard.Severity
            if magnitude >= 6.5 || pager == "orange" || pager == "red" {
                severity = .severe
            } else if magnitude >= 5.5 || pager == "yellow" {
                severity = .moderate
            } else {
                severity = .minor
            }
            return NaturalHazard(
                id: "usgs-\(feature.id)",
                kind: .earthquake,
                name: "M \(magnitude.formatted(.number.precision(.fractionLength(1)))) earthquake",
                coordinate: location,
                severity: severity,
                date: p.time.map { Date(timeIntervalSince1970: $0 / 1000) },
                updated: p.updated.map { Date(timeIntervalSince1970: $0 / 1000) },
                place: p.place,
                summary: nil,
                magnitude: magnitude,
                depth: coordinates.count > 2 ? coordinates[2] : nil,
                mayCauseTsunami: p.tsunami == 1,
                alertLevel: pager?.capitalized,
                explosivity: nil,
                source: .usgs,
                url: p.url.flatMap(URL.init(string:)),
                gdacsEpisode: nil
            )
        }
    }
}

// MARK: - GDACS

extension GDACSEventList {

    private static let gdacsDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()

    /// Current events of every alert level, one per event (its latest
    /// episode). Earthquakes come from USGS instead, which lists more of them.
    var hazards: [NaturalHazard] {
        var latest: [String: Feature] = [:]
        for feature in features {
            let p = feature.properties
            guard p.iscurrent?.value != false, p.eventtype != "EQ" else { continue }
            let id = "gdacs-\(p.eventtype)-\(p.eventid)"
            if let existing = latest[id], (existing.properties.episodeid ?? 0) > (p.episodeid ?? 0) { continue }
            latest[id] = feature
        }
        return latest.compactMap { id, feature in
            let p = feature.properties
            guard let location = feature.geometry?.point else { return nil }
            let kind = DisasterAlert.Kind(rawValue: p.eventtype) ?? .other
            let severity: NaturalHazard.Severity = switch p.alertlevel {
            case "Red": .severe
            case "Orange": .moderate
            default: .minor
            }
            let countries = (p.affectedcountries ?? []).compactMap(\.countryname)
            return NaturalHazard(
                id: id,
                kind: kind,
                name: p.name ?? kind.title,
                coordinate: location,
                severity: severity,
                date: p.fromdate.flatMap(Self.gdacsDateFormatter.date(from:)),
                updated: p.todate.flatMap(Self.gdacsDateFormatter.date(from:)),
                place: countries.isEmpty ? p.country : countries.joined(separator: ", "),
                summary: Self.summary(p.severitydata?.severitytext, kind: kind),
                magnitude: nil,
                depth: nil,
                mayCauseTsunami: false,
                alertLevel: p.alertlevel,
                explosivity: nil,
                source: .gdacs,
                url: p.url?.report.flatMap(URL.init(string:)),
                gdacsEpisode: p.episodeid.map { (p.eventid, $0) }
            )
        }
    }

    /// GDACS's severity line, tidied: "Green impact for forestfire in 6306 ha"
    /// becomes "6,306 ha burned", "Hurricane/Typhoon > 74 mph (maximum wind
    /// speed of 157 km/h)" becomes "Up to 157 km/h"; floods only say
    /// "Magnitude 0", so nothing.
    static func summary(_ text: String?, kind: DisasterAlert.Kind) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        if kind == .flood, text.hasPrefix("Magnitude") { return nil }
        if kind == .wildfire,
           let match = text.firstMatch(of: #/in (\d+) ha/#),
           let hectares = Int(match.1) {
            return "\(hectares.formatted()) ha burned"
        }
        if let match = text.firstMatch(of: #/maximum wind speed of ([^)]+)/#) {
            return "Up to \(match.1)"
        }
        return text
    }
}

/// The shapes GDACS draws for one event. For a cyclone these include its
/// track as two-point line segments, marked as forecast or not.
struct GDACSEventGeometry: Decodable {

    struct Feature: Decodable {
        struct Geometry: Decodable {
            let type: String
            let line: [[Double]]?

            enum CodingKeys: String, CodingKey { case type, coordinates }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                type = try container.decode(String.self, forKey: .type)
                line = type == "LineString" ? try? container.decode([[Double]].self, forKey: .coordinates) : nil
            }
        }
        struct Properties: Decodable {
            let Class: String?
            let forecast: Bool?
        }

        let geometry: Geometry?
        let properties: Properties
    }

    let features: [Feature]

    func track(for hazard: NaturalHazard) -> CycloneTrack? {
        var observed: [[CLLocationCoordinate2D]] = []
        var forecast: [[CLLocationCoordinate2D]] = []
        for feature in features {
            guard feature.properties.Class?.hasPrefix("Line_") == true,
                  let line = feature.geometry?.line?.compactMap(coordinate), line.count >= 2 else { continue }
            if feature.properties.forecast == true {
                forecast.append(line)
            } else {
                observed.append(line)
            }
        }
        guard !observed.isEmpty || !forecast.isEmpty else { return nil }
        return CycloneTrack(hazardID: hazard.id, severity: hazard.severity, observed: observed, forecast: forecast)
    }
}

// MARK: - Smithsonian

/// Eruptions the Smithsonian's Global Volcanism Program lists as continuing,
/// from its GeoServer.
struct GVPEruptionFeed: Decodable {

    struct Feature: Decodable {
        struct Properties: Decodable {
            let VolcanoNumber: Int
            let VolcanoName: String
            let ExplosivityIndexMax: Int?
            /// "yyyyMMdd".
            let StartDate: String?
            let LatitudeDecimal: Double
            let LongitudeDecimal: Double
        }
        let properties: Properties
    }

    let features: [Feature]

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()

    /// "Ruiz, Nevado del" reads as "Nevado del Ruiz".
    static func displayName(_ name: String) -> String {
        let parts = name.components(separatedBy: ", ")
        guard parts.count == 2 else { return name }
        return "\(parts[1]) \(parts[0])"
    }

    var hazards: [NaturalHazard] {
        // One per volcano: the most recent eruption.
        var latest: [Int: Feature.Properties] = [:]
        for feature in features {
            let p = feature.properties
            if let existing = latest[p.VolcanoNumber], (existing.StartDate ?? "") > (p.StartDate ?? "") { continue }
            latest[p.VolcanoNumber] = p
        }
        return latest.values.compactMap { p in
            guard let location = coordinate([p.LongitudeDecimal, p.LatitudeDecimal]) else { return nil }
            return NaturalHazard(
                id: "gvp-\(p.VolcanoNumber)",
                kind: .volcano,
                name: Self.displayName(p.VolcanoName),
                coordinate: location,
                severity: (p.ExplosivityIndexMax ?? 0) >= 4 ? .severe : .moderate,
                date: p.StartDate.flatMap(Self.dateFormatter.date(from:)),
                updated: nil,
                place: nil,
                summary: nil,
                magnitude: nil,
                depth: nil,
                mayCauseTsunami: false,
                alertLevel: nil,
                explosivity: p.ExplosivityIndexMax,
                source: .smithsonian,
                url: URL(string: "https://volcano.si.edu/volcano.cfm?vn=\(p.VolcanoNumber)"),
                gdacsEpisode: nil
            )
        }
    }
}

extension Array where Element == NaturalHazard {
    /// Drops GDACS volcano events at a volcano the Smithsonian already lists,
    /// keeping the Smithsonian's entry.
    func withoutDuplicateVolcanoes() -> [NaturalHazard] {
        let listed = filter { $0.source == .smithsonian }.map(\.coordinate)
        return filter { hazard in
            guard hazard.kind == .volcano, hazard.source == .gdacs else { return true }
            return !listed.contains {
                abs($0.latitude - hazard.coordinate.latitude) < 0.5 && abs($0.longitude - hazard.coordinate.longitude) < 0.5
            }
        }
    }
}
