//
//  FlightAnnotation.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2024-07-26.
//

import MapKit

struct FlightMarker: Equatable, Identifiable, Sendable {
    let id: String
    let latitude: Double
    let longitude: Double
    let track: Float?
    let source: LiveFlight.Source

    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

extension FlightMarker {
    init(flight: LiveFlight) {
        id = flight.id
        latitude = flight.coordinate.latitude
        longitude = flight.coordinate.longitude
        track = flight.track.map(Float.init)
        source = flight.source
    }
}

/// Identity stays stable until the visible markers change, even when live flight details update.
final class FlightMarkerSnapshot: Sendable {
    let markers: [FlightMarker]

    init(_ markers: [FlightMarker]) {
        self.markers = markers
    }
}

final class FlightAnnotation: NSObject, MKAnnotation, Identifiable {
    let id: String
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var track: Float?
    /// Which feed the latest position came from; military aircraft are
    /// drawn in a different colour.
    var source: LiveFlight.Source

    var isMilitary: Bool { source == .adsbLolMilitary }

    init(marker: FlightMarker) {
        id = marker.id
        coordinate = marker.coordinate
        track = marker.track
        source = marker.source
    }
}

extension Array where Element == FlightMarker {
    /// The `limit` flights closest to the centre of `rect`, always including the
    /// flight with `keptID` (the selected one) so its details stay available.
    /// Picking by distance keeps mostly the same aircraft on screen between polls.
    func nearest(to rect: MKMapRect, limit: Int, keeping keptID: String? = nil) -> [FlightMarker] {
        guard count > limit else { return self }
        let center = MKMapPoint(x: rect.midX, y: rect.midY)
        let worldWidth = MKMapRect.world.width

        func squaredDistance(_ annotation: FlightMarker) -> Double {
            if annotation.id == keptID { return -1 }
            let point = MKMapPoint(annotation.coordinate)
            // Measure across the 180° meridian when that is shorter.
            let dx = abs(point.x - center.x)
            let wrappedDx = Swift.min(dx, worldWidth - dx)
            let dy = point.y - center.y
            return wrappedDx * wrappedDx + dy * dy
        }

        return self
            .map { ($0, squaredDistance($0)) }
            .sorted { $0.1 < $1.1 }
            .prefix(limit)
            .map(\.0)
    }
}

