//
//  CableOverlay.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2026-11-05.
//

import MapKit
import UIKit

/// An undersea cable's route on the map: one overlay per cable, made of a
/// polyline per route segment.
final class CableOverlay: MKMultiPolyline {
    private(set) var cableID = ""
    private(set) var color: UIColor = .systemTeal

    convenience init(cable: SubmarineCable) {
        let polylines = cable.lines.map { MKPolyline(coordinates: $0, count: $0.count) }
        self.init(polylines)
        cableID = cable.id
        color = UIColor(hex: cable.colorHex) ?? .systemTeal
    }

    /// Distance from `point` to the nearest part of the route, in map points.
    func distance(to point: MKMapPoint) -> Double {
        var nearest = Double.infinity
        for polyline in polylines {
            let points = polyline.points()
            for index in 0..<max(polyline.pointCount - 1, 0) {
                nearest = min(nearest, Self.distance(from: point, toSegment: points[index], points[index + 1]))
            }
        }
        return nearest
    }

    private static func distance(from p: MKMapPoint, toSegment a: MKMapPoint, _ b: MKMapPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        let t = lengthSquared == 0 ? 0 : max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        let x = a.x + t * dx - p.x, y = a.y + t * dy - p.y
        return (x * x + y * y).squareRoot()
    }
}

/// Where cables come ashore, drawn as a small dot with the place's name in
/// its callout.
final class LandingPointAnnotation: NSObject, MKAnnotation {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let title: String?

    init(point: CableLandingPoint) {
        id = point.id
        coordinate = point.coordinate
        title = point.name
    }
}

final class LandingPointAnnotationView: MKAnnotationView {

    static let reuseIdentifier = "landing-point"

    private static let dot: UIImage = {
        let size = CGSize(width: 8, height: 8)
        return UIGraphicsImageRenderer(size: size).image { context in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            UIColor.white.withAlphaComponent(0.9).setFill()
            context.cgContext.fillEllipse(in: rect)
            UIColor.black.withAlphaComponent(0.5).setStroke()
            context.cgContext.setLineWidth(1)
            context.cgContext.strokeEllipse(in: rect)
        }
    }()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        image = Self.dot
        canShowCallout = true
        // Below aircraft, and hidden by MapKit where dots would overlap.
        displayPriority = .defaultLow
        zPriority = .min
        collisionMode = .circle
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
}

extension UIColor {
    /// "#RRGGBB".
    convenience init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
