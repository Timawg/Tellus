//
//  HazardAnnotation.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2026-11-05.
//

import MapKit
import UIKit

/// A natural hazard on the map.
final class HazardAnnotation: NSObject, MKAnnotation {
    let hazard: NaturalHazard
    var coordinate: CLLocationCoordinate2D { hazard.coordinate }
    var title: String? { hazard.name }

    init(hazard: NaturalHazard) {
        self.hazard = hazard
    }
}

extension NaturalHazard.Severity {
    var color: UIColor {
        switch self {
        case .minor: .systemYellow
        case .moderate: .systemOrange
        case .severe: .systemRed
        }
    }
}

/// A coloured badge with the hazard's symbol: yellow, orange or red by
/// severity. Earthquakes grow with magnitude.
final class HazardAnnotationView: MKAnnotationView {

    static let reuseIdentifier = "hazard"

    /// Badges are drawn once per kind, severity and size and shared.
    private static var images: [String: UIImage] = [:]

    override var annotation: MKAnnotation? {
        didSet { configure() }
    }

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        canShowCallout = false
        collisionMode = .circle
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    private func configure() {
        guard let hazard = (annotation as? HazardAnnotation)?.hazard else { return }
        image = Self.image(for: hazard)
        // Severe hazards always show; MapKit hides lesser ones where they'd
        // overlap. All sit above cable landing points and below aircraft.
        switch hazard.severity {
        case .severe: displayPriority = .required
        case .moderate: displayPriority = .defaultHigh
        case .minor: displayPriority = MKFeatureDisplayPriority(rawValue: 400)
        }
        zPriority = MKAnnotationViewZPriority(rawValue: 200 + Float(hazard.severity.rawValue) * 50)
        accessibilityLabel = "\(hazard.kind.title): \(hazard.name)"
    }

    private static func diameter(for hazard: NaturalHazard) -> CGFloat {
        guard let magnitude = hazard.magnitude else { return 26 }
        // M4.5 → 18 pt, M7 and up → 32 pt.
        return 18 + CGFloat(min(max(magnitude - 4.5, 0), 2.5)) / 2.5 * 14
    }

    private static func image(for hazard: NaturalHazard) -> UIImage {
        let diameter = diameter(for: hazard).rounded()
        let key = "\(hazard.kind.rawValue)-\(hazard.severity.rawValue)-\(diameter)"
        if let image = images[key] { return image }

        let inset: CGFloat = 4
        let canvas = CGSize(width: diameter + inset * 2, height: diameter + inset * 2)
        let circle = CGRect(x: inset, y: inset, width: diameter, height: diameter)
        let configuration = UIImage.SymbolConfiguration(pointSize: diameter * 0.45, weight: .bold)
        let symbol = UIImage(systemName: hazard.kind.symbolName, withConfiguration: configuration)?
            .withTintColor(.white, renderingMode: .alwaysOriginal)

        let image = UIGraphicsImageRenderer(size: canvas).image { context in
            let cg = context.cgContext
            cg.saveGState()
            cg.setShadow(offset: CGSize(width: 0, height: 1), blur: 3, color: UIColor.black.withAlphaComponent(0.5).cgColor)
            hazard.severity.color.setFill()
            cg.fillEllipse(in: circle)
            cg.restoreGState()
            UIColor.white.withAlphaComponent(0.9).setStroke()
            cg.setLineWidth(1.5)
            cg.strokeEllipse(in: circle.insetBy(dx: 0.75, dy: 0.75))
            if let symbol {
                let size = symbol.size
                symbol.draw(in: CGRect(
                    x: circle.midX - size.width / 2,
                    y: circle.midY - size.height / 2,
                    width: size.width,
                    height: size.height
                ))
            }
        }
        images[key] = image
        return image
    }
}

/// A cyclone's track: the path so far, or the forecast, which is drawn dashed.
final class CycloneTrackOverlay: MKMultiPolyline {
    private(set) var hazardID = ""
    private(set) var isForecast = false
    private(set) var severity: NaturalHazard.Severity = .minor

    convenience init(track: CycloneTrack, forecast: Bool) {
        let segments = forecast ? track.forecast : track.observed
        self.init(segments.map { MKPolyline(coordinates: $0, count: $0.count) })
        hazardID = track.hazardID
        isForecast = forecast
        severity = track.severity
    }

    func makeRenderer() -> MKMultiPolylineRenderer {
        let renderer = MKMultiPolylineRenderer(multiPolyline: self)
        renderer.strokeColor = severity.color.withAlphaComponent(isForecast ? 0.7 : 0.9)
        renderer.lineWidth = 3
        renderer.lineCap = .round
        if isForecast {
            renderer.lineDashPattern = [4, 6]
        }
        return renderer
    }
}
