//
//  CountryBorders.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2026-11-05.
//

import Foundation
import MapKit

/// A country's outline, from the bundled Natural Earth borders
/// (Resources/country-borders.geojson, built by scripts/build_country_borders.py).
struct CountryBorder {
    /// ISO 3166-1 alpha-3, as in the app's country list.
    let cca3: String
    let polygons: [MKPolygon]
    /// The part of the country to zoom to: its largest piece and the pieces
    /// that belong with it, leaving out far-off territories such as French
    /// Guiana or Hawaii. Pieces across the 180° meridian are shifted next to
    /// the rest, so the rect can extend past the edge of the world.
    var focusRect: MKMapRect {
        Self.focusRect(of: polygons.map(\.boundingMapRect))
    }

    /// Grows a cluster from the largest piece. A piece joins when it's
    /// within one anchor-size of a piece already in, and either sizeable (at
    /// least 2% of the anchor's area) or right next to it, so specks of
    /// islands far out don't widen the view.
    static func focusRect(of rects: [MKMapRect]) -> MKMapRect {
        guard let anchor = rects.max(by: { $0.width * $0.height < $1.width * $1.height }) else {
            return .null
        }
        let worldWidth = MKMapRect.world.width
        // Shift each piece by a world width when that brings it closer to
        // the anchor, so Chukotka sits next to the rest of Russia.
        let pieces = rects.map { rect -> MKMapRect in
            let dx = rect.midX - anchor.midX
            if dx > worldWidth / 2 { return rect.offsetBy(dx: -worldWidth, dy: 0) }
            if dx < -worldWidth / 2 { return rect.offsetBy(dx: worldWidth, dy: 0) }
            return rect
        }
        let reach = max(anchor.width, anchor.height)
        let anchorArea = anchor.width * anchor.height

        var included = [anchor]
        var remaining = pieces
        var grew = true
        while grew {
            grew = false
            remaining.removeAll { piece in
                let gap = included.map { distance(piece, $0) }.min() ?? .infinity
                let isSizeable = piece.width * piece.height >= anchorArea * 0.02
                guard gap <= reach * 0.05 || (isSizeable && gap <= reach) else { return false }
                included.append(piece)
                grew = true
                return true
            }
        }
        return included.reduce(MKMapRect.null) { $0.union($1) }
    }

    /// Gap between two rects in map points; 0 when they touch or overlap.
    private static func distance(_ a: MKMapRect, _ b: MKMapRect) -> Double {
        let dx = max(0, max(a.minX - b.maxX, b.minX - a.maxX))
        let dy = max(0, max(a.minY - b.maxY, b.minY - a.maxY))
        return (dx * dx + dy * dy).squareRoot()
    }
}

extension CountryBorder {
    /// Rough size of the whole country: the summed bounding areas of its pieces.
    var totalArea: Double {
        polygons.reduce(0) { $0 + $1.boundingMapRect.width * $1.boundingMapRect.height }
    }

    /// The area, in square map points, of this country's piece that contains
    /// `point`, or nil if the point is outside the country.
    func areaOfPiece(containing point: MKMapPoint) -> Double? {
        polygons
            .filter { $0.boundingMapRect.contains(point) && Self.polygon($0, contains: point) }
            .map { $0.boundingMapRect.width * $0.boundingMapRect.height }
            .min()
    }

    /// Even-odd ray casting over the outer ring, minus any holes (lakes,
    /// enclaves such as Lesotho in South Africa).
    private static func polygon(_ polygon: MKPolygon, contains point: MKMapPoint) -> Bool {
        guard ring(polygon.points(), count: polygon.pointCount, contains: point) else { return false }
        return !(polygon.interiorPolygons ?? []).contains { hole in
            ring(hole.points(), count: hole.pointCount, contains: point)
        }
    }

    private static func ring(_ points: UnsafeMutablePointer<MKMapPoint>, count: Int, contains point: MKMapPoint) -> Bool {
        guard count >= 3 else { return false }
        var inside = false
        var j = count - 1
        for i in 0..<count {
            let a = points[i], b = points[j]
            if (a.y > point.y) != (b.y > point.y),
               point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }
}

enum CountryBorders {

    /// The country at `coordinate`. Where outlines overlap the smallest
    /// piece wins, and between identical pieces (Réunion is drawn both on
    /// its own and as part of France) the smaller country, so tapping an
    /// overseas territory picks the territory.
    static func country(at coordinate: CLLocationCoordinate2D, in borders: [String: CountryBorder]) -> String? {
        let point = MKMapPoint(coordinate)
        return borders.values
            .compactMap { border in
                border.areaOfPiece(containing: point).map { (code: border.cca3, piece: $0, total: border.totalArea) }
            }
            .min { ($0.piece, $0.total) < ($1.piece, $1.total) }?
            .code
    }

    /// Every country with an outline, by alpha-3 code. Decoding the file
    /// takes a moment, so call this off the main thread.
    static func load(from url: URL? = Bundle.main.url(forResource: "country-borders", withExtension: "geojson")) throws -> [String: CountryBorder] {
        guard let url else { return [:] }
        let objects = try MKGeoJSONDecoder().decode(try Data(contentsOf: url))
        var borders: [String: CountryBorder] = [:]
        for case let feature as MKGeoJSONFeature in objects {
            guard let data = feature.properties,
                  let properties = try? JSONDecoder().decode([String: String].self, from: data),
                  let code = properties["cca3"] else { continue }
            let polygons = feature.geometry.flatMap { shape -> [MKPolygon] in
                if let multi = shape as? MKMultiPolygon { return multi.polygons }
                if let polygon = shape as? MKPolygon { return [polygon] }
                return []
            }
            guard !polygons.isEmpty else { continue }
            borders[code] = CountryBorder(cca3: code, polygons: polygons)
        }
        return borders
    }
}

extension MKCoordinateRegion {

    /// A region showing `rect` inside the part of the screen the map's
    /// floating controls leave free: below the country card and above the
    /// bottom buttons. `aspectRatio` is the map view's width over height.
    /// Handles rects that run past the 180° meridian.
    init(fitting fullRect: MKMapRect, aspectRatio: Double) {
        // Mercator stretches the poles, so Arctic islands (Franz Josef Land,
        // northern Greenland) would take up most of the view. Fit only up
        // to 72° north and south; the outline still draws beyond.
        let polarLimit = MKMapPoint(CLLocationCoordinate2D(latitude: 72, longitude: 0)).y
        let minY = max(fullRect.minY, polarLimit)
        let maxY = min(fullRect.maxY, MKMapRect.world.height - polarLimit)
        let rect = maxY > minY
            ? MKMapRect(x: fullRect.minX, y: minY, width: fullRect.width, height: maxY - minY)
            : fullRect

        // Fractions of the screen height, from the top, between which the
        // country should sit, and the side margin.
        let freeTop = 0.34, freeBottom = 0.76, sideMargin = 0.06
        let worldWidth = MKMapRect.world.width

        // Very small countries (Vatican, Monaco) still show their
        // surroundings: at least about 30 km across.
        let center = MKMapPoint(x: rect.midX, y: rect.midY)
        let minimumWidth = 30_000 * MKMapPointsPerMeterAtLatitude(center.coordinate.latitude)

        let worldHeight = MKMapRect.world.height
        // Fit the height in the free band, and the width across the screen,
        // but don't zoom out more than 1.6 times the height fit for width
        // alone: on a portrait screen Russia or Canada would otherwise shrink
        // to a sliver, so they run off the sides instead.
        let heightFit = rect.height / (freeBottom - freeTop)
        let widthFit = rect.width / (1 - sideMargin * 2) / aspectRatio
        var height = max(heightFit, min(widthFit, heightFit * 1.6))
        // Near the poles the map can't scroll past the edge of the world, so
        // zooming out further would push the country off its free band (up
        // behind the card for Russia). Stop where it can still sit there.
        let bandCentre = (freeTop + freeBottom) / 2
        let roomAbove = rect.midY / bandCentre
        let roomBelow = (worldHeight - rect.midY) / (1 - bandCentre)
        height = max(heightFit, min(height, roomAbove, roomBelow))
        height = min(max(height, minimumWidth / aspectRatio), worldHeight)
        let width = min(height * aspectRatio, worldWidth)

        // Put the country's middle at the middle of the free band, keeping
        // the view inside the world for countries too big to fit.
        var centerY = rect.midY - ((freeTop + freeBottom) / 2 - 0.5) * height
        centerY = min(max(centerY, height / 2), worldHeight - height / 2)
        let top = MKMapPoint(x: 0, y: max(centerY - height / 2, 0)).coordinate.latitude
        let bottom = MKMapPoint(x: 0, y: min(centerY + height / 2, worldHeight)).coordinate.latitude
        var centerX = rect.midX.truncatingRemainder(dividingBy: worldWidth)
        if centerX < 0 { centerX += worldWidth }
        let centerCoordinate = MKMapPoint(x: centerX, y: min(max(centerY, 0), worldHeight)).coordinate

        self.init(
            center: centerCoordinate,
            span: MKCoordinateSpan(
                latitudeDelta: min(top - bottom, 180),
                longitudeDelta: min(width / worldWidth * 360, 360)
            )
        )
    }
}
