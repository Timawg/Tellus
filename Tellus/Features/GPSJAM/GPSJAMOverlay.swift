import MapKit
import SwiftyH3

struct GPSJAMCell: Identifiable {
    enum Level: CaseIterable {
        case elevated, high

        var color: CGColor {
            switch self {
            case .elevated: CGColor(red: 1, green: 0.69, blue: 0.13, alpha: 0.55)
            case .high: CGColor(red: 1, green: 0.22, blue: 0.23, alpha: 0.66)
            }
        }
    }

    let index: UInt64
    let day: String
    let good: Int
    let bad: Int

    var id: UInt64 { index }
    var total: Int { good + bad }
    var observedShare: Double { total > 0 ? Double(bad) / Double(total) : 0 }

    /// GPSJAM discounts one low-accuracy aircraft to suppress isolated reports.
    var adjustedShare: Double { total > 0 ? Double(max(0, bad - 1)) / Double(total) : 0 }

    var level: Level? {
        guard total >= 5 else { return nil }
        if adjustedShare > 0.10 { return .high }
        if adjustedShare >= 0.02 { return .elevated }
        return nil
    }
}

final class GPSJAMOverlay: NSObject, MKOverlay {
    struct Shape {
        let points: [MKMapPoint]
        let bounds: MKMapRect

        init(points: [MKMapPoint]) {
            self.points = points
            let xs = points.map(\.x)
            let ys = points.map(\.y)
            let minX = xs.min() ?? 0
            let minY = ys.min() ?? 0
            bounds = MKMapRect(x: minX, y: minY, width: (xs.max() ?? minX) - minX, height: (ys.max() ?? minY) - minY)
        }
    }

    let day: String
    let coordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    let boundingMapRect = MKMapRect.world
    let shapes: [GPSJAMCell.Level: [Shape]]
    private let cells: [UInt64: GPSJAMCell]

    init(day: String, cells: [GPSJAMCell]) {
        self.day = day
        var indexed: [UInt64: GPSJAMCell] = [:]
        var shapes: [GPSJAMCell.Level: [Shape]] = [:]
        for cell in cells {
            let hex = H3Cell(cell.index)
            guard let level = cell.level, indexed[cell.index] == nil, hex.isValid, (try? hex.resolution) == .res4,
                  let boundary = try? hex.boundary, let first = boundary.first else { continue }
            let worldWidth = MKMapRect.world.width
            let anchor = MKMapPoint(first.coordinates).x
            let points = boundary.map { vertex in
                let point = MKMapPoint(vertex.coordinates)
                // Keep a dateline cell together in one copy of the world.
                let wraps = ((point.x - anchor) / worldWidth).rounded()
                return MKMapPoint(x: point.x - wraps * worldWidth, y: point.y)
            }
            indexed[cell.index] = cell
            shapes[level, default: []].append(Shape(points: points))
        }
        self.cells = indexed
        self.shapes = shapes
    }

    func cell(at coordinate: CLLocationCoordinate2D) -> GPSJAMCell? {
        guard CLLocationCoordinate2DIsValid(coordinate),
              let hex = try? H3LatLng(latitudeDegs: coordinate.latitude, longitudeDegs: coordinate.longitude)
                .cell(at: .res4) else { return nil }
        return cells[hex.id]
    }
}

final class GPSJAMOverlayRenderer: MKOverlayRenderer {
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let overlay = overlay as? GPSJAMOverlay else { return }

        let worldWidth = MKMapRect.world.width
        for level in GPSJAMCell.Level.allCases {
            let path = CGMutablePath()
            for copy in -1...1 {
                let offset = Double(copy) * worldWidth
                let visible = mapRect.offsetBy(dx: -offset, dy: 0)
                for shape in overlay.shapes[level, default: []] where shape.bounds.intersects(visible) {
                    for (index, vertex) in shape.points.enumerated() {
                        let point = point(for: MKMapPoint(x: vertex.x + offset, y: vertex.y))
                        if index == 0 {
                            path.move(to: point)
                        } else {
                            path.addLine(to: point)
                        }
                    }
                    path.closeSubpath()
                }
            }
            context.addPath(path)
            context.setFillColor(level.color)
            context.fillPath()
        }
    }
}
