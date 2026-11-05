//
//  FlightAnnotationMarkerView.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2024-07-25.
//

import Foundation
import MapKit

final class FlightMarkerAnnotationView: MKAnnotationView {
    
    private var imageView: UIImageView?

    private static let aircraftSize = CGSize(width: 20, height: 25)
    private static let shadowInset: CGFloat = 4

    /// The aircraft with its drop shadow drawn in, made once and shared by every
    /// marker. A live layer shadow is worked out again for each marker on every
    /// frame, which gets expensive with hundreds of aircraft on screen.
    static let shadowedImage = makeImage(tint: nil)
    /// The same marker tinted green, for military aircraft.
    static let militaryImage = makeImage(tint: .militaryAircraft)

    private static func makeImage(tint: UIColor?) -> UIImage {
        var image = UIImage(imageLiteralResourceName: "aircraft")
        if let tint {
            image = UIGraphicsImageRenderer(size: aircraftSize).image { context in
                let rect = CGRect(origin: .zero, size: aircraftSize)
                image.draw(in: rect)
                tint.withAlphaComponent(0.75).setFill()
                context.fill(rect, blendMode: .sourceAtop)
            }
        }
        let canvas = CGSize(
            width: aircraftSize.width + shadowInset * 2,
            height: aircraftSize.height + shadowInset * 2
        )
        return UIGraphicsImageRenderer(size: canvas).image { context in
            context.cgContext.setShadow(
                offset: CGSize(width: 0, height: 1),
                blur: 5,
                color: UIColor.black.withAlphaComponent(0.5).cgColor
            )
            image.draw(in: CGRect(origin: CGPoint(x: shadowInset, y: shadowInset), size: aircraftSize))
        }
    }

    override var annotation: MKAnnotation? {
        didSet { applySource() }
    }

    /// Picks the marker colour for the annotation's feed.
    func applySource() {
        let isMilitary = (annotation as? FlightAnnotation)?.isMilitary == true
        imageView?.image = isMilitary ? Self.militaryImage : Self.shadowedImage
        accessibilityLabel = isMilitary ? "Military aircraft" : "Aircraft"
    }

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setupImageView()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setupImageView()
    }
    
    private func setupImageView() {
        // The shadow is part of the image, so it helps aircraft stand out against
        // the map without per-marker shadow rendering.
        let imageView = UIImageView(image: Self.shadowedImage)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        self.imageView = imageView

        applySource()

        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            imageView.heightAnchor.constraint(equalToConstant: Self.shadowedImage.size.height),
            imageView.widthAnchor.constraint(equalToConstant: Self.shadowedImage.size.width),
        ])
    }
}

extension UIColor {
    /// Military aircraft are drawn in this green, so they stand apart from
    /// civil flights and from the yellow-to-red hazard badges.
    static let militaryAircraft = UIColor(red: 0.6, green: 0.8, blue: 0.35, alpha: 1)
}
