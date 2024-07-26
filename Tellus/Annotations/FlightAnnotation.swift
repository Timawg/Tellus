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

