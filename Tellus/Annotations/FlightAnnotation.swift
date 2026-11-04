//
//  FlightAnnotation.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2024-07-26.
//

import MapKit

final class FlightAnnotation: NSObject, MKAnnotation, Identifiable {
    let id: String
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var track: Float?
    
    init(id: String, coordinate: CLLocationCoordinate2D, track: Float?) {
        self.id = id
        self.coordinate = coordinate
        self.track = track
    }
}

extension Array where Element == FlightAnnotation {
    /// The `limit` flights closest to the centre of `rect`, always including the
    /// flight with `keptID` (the selected one) so its details stay available.
    /// Picking by distance keeps mostly the same aircraft on screen between polls.
    func nearest(to rect: MKMapRect, limit: Int, keeping keptID: String? = nil) -> [FlightAnnotation] {
        guard count > limit else { return self }
        let center = MKMapPoint(x: rect.midX, y: rect.midY)
        let worldWidth = MKMapRect.world.width

        func squaredDistance(_ annotation: FlightAnnotation) -> Double {
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

