import MapKit

final class AuroraOverlay: NSObject, MKOverlay, @unchecked Sendable {
    enum Band: CaseIterable {
        case faint, green, teal, amber

        init?(value: Int) {
            switch value {
            case 1...4: self = .faint
            case 5...19: self = .green
            case 20...49: self = .teal
            case 50...100: self = .amber
            default: return nil
            }
        }

        var color: CGColor {
            switch self {
            case .faint: CGColor(red: 0.27, green: 0.9, blue: 0.46, alpha: 0.22)
            case .green: CGColor(red: 0.24, green: 0.95, blue: 0.39, alpha: 0.52)
            case .teal: CGColor(red: 0.13, green: 0.98, blue: 0.78, alpha: 0.65)
            case .amber: CGColor(red: 1, green: 0.71, blue: 0.2, alpha: 0.78)
            }
        }
    }

    let validAt: Date
    let coordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    let boundingMapRect = MKMapRect.world
    let bands: [Band: [MKMapRect]]

    init(validAt: Date, coordinates: [[Int]]) throws {
        guard !coordinates.isEmpty else { throw HTTPError.invalidResponse }
        self.validAt = validAt

        // NOAA uses 0...359° longitude. In map coordinates column zero is
        // centered on the date line, so its cell straddles the world edge.
        let longitudes = 360
        var grid = Array(repeating: 0, count: 181 * longitudes)
        for sample in coordinates {
            guard sample.count == 3, (0..<longitudes).contains(sample[0]),
                  (-90...90).contains(sample[1]), (0...100).contains(sample[2]) else {
                throw HTTPError.invalidResponse
            }
            let column = (sample[0] + 180) % longitudes
            grid[(sample[1] + 90) * longitudes + column] = sample[2]
        }

        let width = MKMapRect.world.width / Double(longitudes)
        var bands: [Band: [MKMapRect]] = [:]
        // Web Mercator's latitude limit falls inside the ±85° cells.
        for latitude in -85...85 {
            let north = Self.mapY(latitude: Double(latitude) + 0.5)
            let south = Self.mapY(latitude: Double(latitude) - 0.5)
            let row = (latitude + 90) * longitudes
            var start = 0
            var band = Band(value: grid[row])
            // Join adjacent cells in the same band before drawing.
            for column in 1...longitudes {
                let next = column < longitudes ? Band(value: grid[row + column]) : nil
                guard next != band else { continue }
                if let band {
                    bands[band, default: []].append(MKMapRect(
                        x: (Double(start) - 0.5) * width, y: north,
                        width: Double(column - start) * width, height: south - north
                    ))
                }
                start = column
                band = next
            }
        }
        self.bands = bands
    }

    func isOlder(at date: Date) -> Bool {
        date.timeIntervalSince(validAt) >= 30 * 60
    }

    private static func mapY(latitude: Double) -> Double {
        let limit = atan(sinh(Double.pi)) * 180 / Double.pi
        return MKMapPoint(CLLocationCoordinate2D(latitude: min(limit, max(-limit, latitude)), longitude: 0)).y
    }
}

final class AuroraOverlayRenderer: MKOverlayRenderer {
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let aurora = overlay as? AuroraOverlay else { return }
        let worldWidth = MKMapRect.world.width
        context.saveGState()
        defer { context.restoreGState() }
        context.setShouldAntialias(false)
        for band in AuroraOverlay.Band.allCases {
            let path = CGMutablePath()
            for copy in -1...1 {
                let offset = Double(copy) * worldWidth
                let visible = mapRect.offsetBy(dx: -offset, dy: 0)
                for cell in aurora.bands[band, default: []] where cell.intersects(visible) {
                    path.addRect(rect(for: cell.offsetBy(dx: offset, dy: 0)))
                }
            }
            context.addPath(path)
            context.setFillColor(band.color)
            context.fillPath()
        }
    }
}
