//
//  CGAffineTransform.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2024-07-31.
//

import Foundation

extension CGAffineTransform {
    init(rotationDegrees degrees: CGFloat) {
        self.init(rotationAngle: degrees * .pi / 180.0)
    }
    
    var rotationDegrees: CGFloat {
        atan2(b, a) * .pi / 180.0
    }

    func rotatedBy(degrees: CGFloat) -> CGAffineTransform {
        self.rotated(by: degrees * .pi / 180.0)
    }
    
    func rotate(to degrees: CGFloat) -> CGAffineTransform {
        let current = rotationDegrees
        let difference = degrees - current
        return self.rotatedBy(degrees: difference)
    }
}
