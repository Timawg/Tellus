//
//  CountryOutlineOverlay.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2026-11-05.
//

import MapKit
import UIKit

/// The selected country's outline: a bright border with a faint fill,
/// drawn under cables and cyclone tracks.
final class CountryOutlineOverlay: MKMultiPolygon {
    private(set) var cca3 = ""

    convenience init(border: CountryBorder) {
        self.init(border.polygons)
        cca3 = border.cca3
    }

    func makeRenderer() -> MKMultiPolygonRenderer {
        let renderer = MKMultiPolygonRenderer(multiPolygon: self)
        renderer.strokeColor = UIColor.white.withAlphaComponent(0.9)
        renderer.fillColor = UIColor.white.withAlphaComponent(0.08)
        renderer.lineWidth = 2
        renderer.lineJoin = .round
        return renderer
    }
}
