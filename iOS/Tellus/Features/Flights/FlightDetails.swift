//
//  FlightDetails.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2026-11-04.
//

import Foundation
import CoreLocation

/// An aircraft's registration details from adsbdb.com, looked up by its
/// ICAO 24-bit address.
struct AircraftInfo: Decodable, Equatable, Sendable {
    let type: String?
    let icaoType: String?
    let manufacturer: String?
    let registration: String?
    let registeredOwner: String?
    let registeredOwnerCountryName: String?
    let urlPhoto: String?

    /// "Boeing 737-8AS", or whichever part is known.
    var displayType: String? {
        let parts = [manufacturer, type].compactMap { $0?.isEmpty == false ? $0 : nil }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

/// A flight's scheduled route from adsbdb.com, looked up by callsign.
struct FlightRoute: Decodable, Equatable, Sendable {

    struct Airline: Decodable, Equatable, Sendable {
        let name: String?
        let iata: String?
        let icao: String?
    }

    struct Airport: Decodable, Equatable, Sendable {
        let name: String
        let municipality: String?
        let countryName: String?
        let iataCode: String?
        let icaoCode: String?
        let latitude: Double
        let longitude: Double

        /// IATA code (FRA) if it has one, otherwise ICAO (EDDF).
        var code: String {
            iataCode ?? icaoCode ?? "—"
        }

        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }

        var location: CLLocation {
            CLLocation(latitude: latitude, longitude: longitude)
        }
    }

    let callsign: String
    /// The flight number passengers see, e.g. EN8HK for callsign DLA8HK.
    let callsignIata: String?
    let airline: Airline?
    let origin: Airport
    let destination: Airport

    func mapCoordinates(through aircraft: CLLocationCoordinate2D) -> [CLLocationCoordinate2D]? {
        guard hasValidAirportCoordinates, CLLocationCoordinate2DIsValid(aircraft),
              origin.location.distance(from: destination.location) > 0 else { return nil }
        return [origin.coordinate, aircraft, destination.coordinate]
    }

    private var hasValidAirportCoordinates: Bool {
        CLLocationCoordinate2DIsValid(origin.coordinate) && CLLocationCoordinate2DIsValid(destination.coordinate)
    }

    /// How far along the route the aircraft is, measured via its position.
    func progress(forAircraftAt position: CLLocation) -> (flown: CLLocationDistance, remaining: CLLocationDistance, fraction: Double) {
        let flown = origin.location.distance(from: position)
        let remaining = position.distance(from: destination.location)
        let total = flown + remaining
        return (flown, remaining, total > 0 ? flown / total : 0)
    }

    /// Routes are crowd-sourced and keyed only by callsign, so they can be
    /// stale or belong to another leg of a multi-stop flight. A route is only
    /// believable if the aircraft is roughly between its two airports: the
    /// detour via the aircraft's position may be at most 25% (plus 300 km for
    /// departures, arrivals and holding patterns) longer than the direct route.
    func isPlausible(forAircraftAt position: CLLocation) -> Bool {
        guard hasValidAirportCoordinates, CLLocationCoordinate2DIsValid(position.coordinate) else { return false }
        let direct = origin.location.distance(from: destination.location)
        let viaAircraft = origin.location.distance(from: position) + position.distance(from: destination.location)
        return viaAircraft <= direct * 1.25 + 300_000
    }
}
