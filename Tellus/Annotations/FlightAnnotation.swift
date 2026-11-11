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
    /// Samples occupied cells across the viewport, reserving a place for the
    /// selected flight if it is visible. All visible flights fit below the limit.
    func distributed(
        in rect: MKMapRect,
        limit: Int,
        keeping selectedID: String? = nil
    ) -> (markers: [FlightMarker], visibleCount: Int) {
        guard rect.minX.isFinite, rect.minY.isFinite,
              rect.width.isFinite, rect.width > 0,
              rect.height.isFinite, rect.height > 0 else { return ([], 0) }

        let worldWidth = MKMapRect.world.width
        let width = Swift.min(rect.width, worldWidth)
        let visible: [(marker: FlightMarker, x: Double, y: Double)] = compactMap { marker in
            guard CLLocationCoordinate2DIsValid(marker.coordinate) else { return nil }
            let point = MKMapPoint(marker.coordinate)
            // Measure east from the viewport's left edge, wrapping at the date line.
            let offset = (point.x - rect.minX).truncatingRemainder(dividingBy: worldWidth)
            let x = offset < 0 ? offset + worldWidth : offset
            let y = point.y - rect.minY
            guard (0...width).contains(x), (0...rect.height).contains(y) else { return nil }
            return (marker, x, y)
        }

        guard limit > 0 else { return ([], visible.count) }
        guard visible.count > limit else { return (visible.map(\.marker), visible.count) }

        // Use at most one cell per available slot, with roughly square cells
        // in map coordinates. Every occupied cell can then contribute a marker.
        let aspectRatio = Swift.min(Double(limit), Swift.max(1 / Double(limit), width / rect.height))
        let columns = Swift.max(1, Int((Double(limit) * aspectRatio).squareRoot()))
        let rows = limit / columns
        var cells = [[FlightMarker]](repeating: [], count: rows * columns)
        for (marker, x, y) in visible {
            let column = Swift.min(columns - 1, Int(x / width * Double(columns)))
            let row = Swift.min(rows - 1, Int(y / rect.height * Double(rows)))
            cells[row * columns + column].append(marker)
        }

        var occupied = cells.filter { !$0.isEmpty }.map { cell in
            cell.sorted { lhs, rhs in
                if lhs.id == selectedID { return rhs.id != selectedID }
                if rhs.id == selectedID { return false }
                return lhs.id < rhs.id
            }[...]
        }
        var sample: [FlightMarker] = []
        sample.reserveCapacity(limit)
        while sample.count < limit, !occupied.isEmpty {
            let slots = Swift.min(limit - sample.count, occupied.count)
            // Spread a partial round across the remaining occupied cells too.
            for slot in 0..<slots {
                let index = Int((Double(slot) + 0.5) * Double(occupied.count) / Double(slots))
                if let marker = occupied[index].popFirst() {
                    sample.append(marker)
                }
            }
            occupied.removeAll(where: \.isEmpty)
        }
        return (sample, visible.count)
    }
}

