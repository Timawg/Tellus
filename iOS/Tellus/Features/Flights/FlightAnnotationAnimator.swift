//
//  FlightAnnotationAnimator.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2024-07-30.
//

import UIKit

@MainActor
struct FlightAnnotationAnimator {
    static func animateSelect(view: FlightMarkerAnnotationView?) {
        guard let view else { return }
        UIView.animate(withDuration: 0.25) {
            applyTransform(to: view, selected: true)
        }
    }

    static func animateDeselect(view: FlightMarkerAnnotationView?) {
        guard let view else { return }
        UIView.animate(withDuration: 0.25) {
            applyTransform(to: view, selected: false)
        }
    }

    static func applyTransform(to view: FlightMarkerAnnotationView, selected: Bool) {
        let heading = (view.annotation as? FlightAnnotation)?.track ?? 0
        let scale: CGFloat = selected ? 1.5 : 1
        view.transform = CGAffineTransform(rotationDegrees: CGFloat(heading)).scaledBy(x: scale, y: scale)
    }
}
