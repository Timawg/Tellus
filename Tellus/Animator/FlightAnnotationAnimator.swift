//
//  FlightAnnotationAnimator.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2024-07-30.
//

import Foundation
import UIKit

struct FlightAnnotationAnimator {
    
    static func animateSelect(view: FlightMarkerAnnotationView?) {
        guard let view else {
            return
        }
        UIView.animate(withDuration: 0.25) {
            view.transform = view.transform.scaledBy(x: 1.5, y: 1.5)
        }
    }

    static func animateDeselect(view: FlightMarkerAnnotationView?) {
        guard let view else {
            return
        }

        UIView.animate(withDuration: 0.25) {
            view.transform = view.transform.scaledBy(x: 0.75, y: 0.75)
        }
    }
}
