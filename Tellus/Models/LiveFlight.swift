//
//  LiveFlight.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2026-11-05.
//

import Foundation
import CoreLocation

/// An aircraft's latest position and live values, whichever feed it came
/// from. OpenSky covers civil and military traffic in the visible area;
/// adsb.lol's military list replaces OpenSky's data for the aircraft it
/// knows to be military, which are then drawn in a different colour.
struct LiveFlight: Identifiable, Equatable, Sendable {

    enum Source: Sendable {
        case openSky
        /// adsb.lol's list of aircraft flagged as military.
        case adsbLolMilitary
    }

    /// ICAO 24-bit address in lowercase hex, e.g. "ae1ffc".
    let id: String
    let callsign: String?
    let coordinate: CLLocationCoordinate2D
    /// Degrees clockwise from north.
    let track: Double?
    let altitudeMeters: Double?
    let isOnGround: Bool
    let speedMetersPerSecond: Double?
    let verticalRateMetersPerSecond: Double?
    let squawk: String?
    /// OpenSky: country of registration, from the address block.
    let originCountry: String?
    /// adsb.lol: ICAO type designator, e.g. "C17", and registration.
    let typeCode: String?
    let registration: String?
    /// adsb.lol: "general", "nordo", "unlawful"…; nil when there is none.
    let emergency: String?
    let lastContact: Date
    let source: Source

    var isMilitary: Bool { source == .adsbLolMilitary }

    static func == (lhs: LiveFlight, rhs: LiveFlight) -> Bool {
        lhs.id == rhs.id
            && lhs.source == rhs.source
            && lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
            && lhs.track == rhs.track
            && lhs.lastContact == rhs.lastContact
    }
}

extension LiveFlight {
    init?(state: StateVector) {
        guard let latitude = state.latitude, let longitude = state.longitude else { return nil }
        let callsign = state.callsign?.trimmingCharacters(in: .whitespaces)
        self.init(
            id: state.icao24.lowercased(),
            callsign: callsign?.isEmpty == false ? callsign : nil,
            coordinate: CLLocationCoordinate2D(latitude: CLLocationDegrees(latitude), longitude: CLLocationDegrees(longitude)),
            track: state.trueTrack.map(Double.init),
            altitudeMeters: (state.geoAltitude ?? state.baroAltitude).map(Double.init),
            isOnGround: state.onGround,
            speedMetersPerSecond: state.velocity.map(Double.init),
            verticalRateMetersPerSecond: state.verticalRate.map(Double.init),
            squawk: state.squawk,
            originCountry: state.originCountry,
            typeCode: nil,
            registration: nil,
            emergency: nil,
            lastContact: Date(timeIntervalSince1970: TimeInterval(state.lastContact)),
            source: .openSky
        )
    }
}

extension Array where Element == LiveFlight {
    /// OpenSky's flights with adsb.lol's military aircraft merged in by ICAO
    /// address. A military entry replaces the OpenSky one for the same
    /// aircraft; military aircraft OpenSky didn't list are added, so they
    /// still show while OpenSky is rate limiting us.
    func merging(military: [LiveFlight]) -> [LiveFlight] {
        guard !military.isEmpty else { return self }
        let militaryByID = Dictionary(military.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let replaced = map { militaryByID[$0.id] ?? $0 }
        let listed = Set(map(\.id))
        return replaced + military.filter { !listed.contains($0.id) }
    }
}

// MARK: - adsb.lol

/// adsb.lol's readsb-style aircraft list.
struct ADSBLolAircraftList: Decodable {

    struct Aircraft: Decodable {
        /// A number of feet, or "ground".
        enum Altitude: Decodable {
            case feet(Double)
            case ground

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let feet = try? container.decode(Double.self) {
                    self = .feet(feet)
                } else {
                    _ = try container.decode(String.self)
                    self = .ground
                }
            }
        }

        let hex: String
        let flight: String?
        let r: String?
        let t: String?
        let alt_baro: Altitude?
        let alt_geom: Double?
        /// Knots.
        let gs: Double?
        let track: Double?
        let true_heading: Double?
        /// Feet per minute.
        let baro_rate: Double?
        let geom_rate: Double?
        let squawk: String?
        let emergency: String?
        let category: String?
        let lat: Double?
        let lon: Double?
        /// Seconds since the position was received.
        let seen_pos: Double?
    }

    /// Milliseconds since 1970 when the list was made.
    let now: Double?
    let ac: [Aircraft]

    /// Type designators for ground vehicles and fixed transmitters, which
    /// some military sites broadcast.
    private static let nonAircraftTypes: Set<String> = ["TWR", "GND", "SERV", "EMER"]

    private static let metersPerFoot = 0.3048
    private static let metersPerSecondPerKnot = 0.514444

    /// Aircraft with a position from the last minute. Surface vehicles
    /// (category C*) and transmitters are left out.
    func flights(receivedAt fallback: Date = Date()) -> [LiveFlight] {
        let listTime = now.map { Date(timeIntervalSince1970: $0 / 1000) } ?? fallback
        return ac.compactMap { a in
            guard let lat = a.lat, let lon = a.lon,
                  (-90...90).contains(lat), (-180...180).contains(lon),
                  (a.seen_pos ?? 0) <= 60,
                  a.category?.hasPrefix("C") != true,
                  !Self.nonAircraftTypes.contains(a.t ?? "") else { return nil }
            let callsign = a.flight?.trimmingCharacters(in: .whitespaces)
            var altitudeFeet: Double?
            var onGround = false
            switch a.alt_baro {
            case .feet(let feet): altitudeFeet = a.alt_geom ?? feet
            case .ground: onGround = true
            case nil: altitudeFeet = a.alt_geom
            }
            return LiveFlight(
                id: a.hex.lowercased(),
                callsign: callsign?.isEmpty == false ? callsign : nil,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                track: a.track ?? a.true_heading,
                altitudeMeters: altitudeFeet.map { $0 * Self.metersPerFoot },
                isOnGround: onGround,
                speedMetersPerSecond: a.gs.map { $0 * Self.metersPerSecondPerKnot },
                verticalRateMetersPerSecond: (a.baro_rate ?? a.geom_rate).map { $0 * Self.metersPerFoot / 60 },
                squawk: a.squawk,
                originCountry: nil,
                typeCode: a.t?.isEmpty == false ? a.t : nil,
                registration: a.r?.isEmpty == false ? a.r : nil,
                emergency: a.emergency.flatMap { $0 == "none" ? nil : $0 },
                lastContact: listTime.addingTimeInterval(-(a.seen_pos ?? 0)),
                source: .adsbLolMilitary
            )
        }
    }
}
