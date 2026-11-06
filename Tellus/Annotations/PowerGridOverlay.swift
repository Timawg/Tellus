import ImageIO
import MapKit
import UniformTypeIdentifiers

final class PowerGridOverlay: MKTileOverlay {
    private final class Tile {
        let grid: PowerGridTile
        let png: Data

        init(grid: PowerGridTile, png: Data) {
            self.grid = grid
            self.png = png
        }
    }

    private let tiles = NSCache<NSString, Tile>()

    init() {
        super.init(urlTemplate: "https://openinframap.org/map/power/{z}/{x}/{y}.pbf")
        minimumZ = 4
        maximumZ = 17
        canReplaceMapContent = false
        tiles.countLimit = 96
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let key = Self.key(x: path.x, y: path.y, zoom: path.z)
        if let tile = tiles.object(forKey: key) {
            result(tile.png, nil)
            return
        }

        super.loadTile(at: path) { [weak self] data, error in
            guard let data else {
                result(nil, error)
                return
            }
            do {
                let grid = try PowerGridTile(data: data)
                guard let png = Self.render(grid) else { throw URLError(.cannotDecodeContentData) }
                self?.tiles.setObject(Tile(grid: grid, png: png), forKey: key)
                result(png, nil)
            } catch {
                result(nil, error)
            }
        }
    }

    func asset(at point: MKMapPoint, mapPointsPerScreenPoint: Double) -> PowerGridAsset? {
        let worldWidth = MKMapRect.world.width
        let size = Double(PowerGridTile.size)
        let zoom = log2(worldWidth / (mapPointsPerScreenPoint * size))
        guard zoom.isFinite, zoom >= 7, (0..<worldWidth).contains(point.y) else { return nil }

        let level = min(maximumZ, Int(zoom.rounded()))
        let x = (point.x / worldWidth).truncatingRemainder(dividingBy: 1)
        let y = point.y / worldWidth
        for z in [level, level - 1, level + 1] where (minimumZ...maximumZ).contains(z) {
            let tileCount = Double(1 << z)
            let column = (x < 0 ? x + 1 : x) * tileCount
            let row = y * tileCount
            let tileX = Int(column)
            let tileY = Int(row)
            guard let tile = tiles.object(forKey: Self.key(x: tileX, y: tileY, zoom: z)) else { continue }

            let local = CGPoint(x: (column - Double(tileX)) * size, y: (row - Double(tileY)) * size)
            let tolerance = CGFloat(8 * mapPointsPerScreenPoint * tileCount * size / worldWidth)
            if let asset = tile.grid.asset(at: local, tolerance: tolerance) { return asset }
        }
        return nil
    }

    private static func key(x: Int, y: Int, zoom: Int) -> NSString {
        "\(zoom)/\(x)/\(y)" as NSString
    }

    static func render(_ grid: PowerGridTile) -> Data? {
        let size = PowerGridTile.size
        guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: 0, y: CGFloat(size))
        context.scaleBy(x: 1, y: -1)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for kind in PowerGridAsset.Kind.allCases {
            context.setStrokeColor(kind.color)
            for feature in grid.features where feature.kind == kind {
                context.addPath(feature.path)
                switch feature.geometry {
                case .line:
                    context.setLineWidth((feature.asset?.voltage ?? 0) >= 220 ? 2 : 1.25)
                    context.strokePath()
                case .point:
                    context.setFillColor(kind.color)
                    context.fillPath(using: .evenOdd)
                case .area:
                    context.setFillColor(kind.color.copy(alpha: 0.25) ?? kind.color)
                    context.setLineWidth(1)
                    context.drawPath(using: .eoFillStroke)
                }
            }
        }
        let png = NSMutableData()
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? png as Data : nil
    }
}

extension PowerGridAsset.Kind {
    var color: CGColor {
        switch self {
        case .line: CGColor(red: 1, green: 0.73, blue: 0.24, alpha: 0.95)
        case .substation: CGColor(red: 0.28, green: 0.82, blue: 1, alpha: 0.95)
        case .plant: CGColor(red: 1, green: 0.43, blue: 0.54, alpha: 0.95)
        }
    }
}
