import ImageIO
import MapKit
import UIKit
import UniformTypeIdentifiers

/// The hemisphere where the centre of the Sun is below the horizon.
final class NightOverlay: NSObject, MKOverlay {
    let coordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    let boundingMapRect = MKMapRect.world
    fileprivate let boundary: [MKMapPoint]

    init(date: Date) {
        // US Naval Observatory: https://aa.usno.navy.mil/faq/sun_approx
        let days = date.timeIntervalSince1970 / 86_400 - 10_957.5
        let radians = Double.pi / 180
        let anomaly = (357.529 + 0.98560028 * days) * radians
        let meanLongitude = (280.459 + 0.98564736 * days)
            .truncatingRemainder(dividingBy: 360) * radians
        let eclipticLongitude = meanLongitude + (1.915 * sin(anomaly) + 0.020 * sin(2 * anomaly)) * radians
        let obliquity = (23.439 - 0.00000036 * days) * radians
        let rightAscension = atan2(cos(obliquity) * sin(eclipticLongitude), cos(eclipticLongitude))
        let declination = asin(sin(obliquity) * sin(eclipticLongitude))
        let equationOfTime = meanLongitude - rightAscension
        let utcDays = date.timeIntervalSince1970 / 86_400
        let fractionOfDay = utcDays - floor(utcDays)
        // Longitude of solar midnight, wrapped to [-180, 180].
        let midnight = (-360 * fractionOfDay - equationOfTime / radians).remainder(dividingBy: 360)

        let world = MKMapRect.world
        let latitudeLimit = atan(sinh(Double.pi)) / radians
        let tilt = tan(declination)
        var latitudes = Array(stride(from: -latitudeLimit, to: latitudeLimit, by: 0.25))
        latitudes.append(latitudeLimit)
        if tilt != 0 {
            // Also sample by longitude to keep the curve smooth where the
            // terminator turns sharply into a region of polar day or night.
            for width in stride(from: 0.0, through: 180, by: 0.5) {
                let latitude = atan(cos(width * radians) / tilt) / radians
                if abs(latitude) < latitudeLimit {
                    latitudes.append(latitude)
                }
            }
        }

        var west: [MKMapPoint] = []
        var east: [MKMapPoint] = []
        for latitude in latitudes.sorted() {
            // Solve for solar elevation zero at this latitude. Clamping
            // gives an empty or full band during polar day or night.
            let cosine = tan(latitude * radians) * tilt
            let halfWidth = acos(min(1, max(-1, cosine))) / radians
            let y = MKMapPoint(CLLocationCoordinate2D(latitude: latitude, longitude: 0)).y
            // Keep x unwrapped so a band crossing the date line stays intact.
            west.append(MKMapPoint(x: (midnight - halfWidth + 180) / 360 * world.width, y: y))
            east.append(MKMapPoint(x: (midnight + halfWidth + 180) / 360 * world.width, y: y))
        }
        boundary = west + east.reversed()
    }
}

final class NightOverlayRenderer: MKOverlayPathRenderer {
    private let boundary: [MKMapPoint]

    init(night: NightOverlay) {
        boundary = night.boundary
        super.init(overlay: night)
        fillColor = UIColor(red: 0.03, green: 0.02, blue: 0.12, alpha: 0.5)
    }

    override func createPath() {
        let shade = CGMutablePath()
        // Repeat on either side so the night also draws across the date line.
        for copy in -1...1 {
            let offset = Double(copy) * MKMapRect.world.width
            let points = boundary.map { point(for: MKMapPoint(x: $0.x + offset, y: $0.y)) }
            shade.addLines(between: points)
            shade.closeSubpath()
        }
        path = shade
    }
}

/// Render the grayscale radiance as white lights with a transparent background.
final class NightLightsTileOverlay: MKTileOverlay {
    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        super.loadTile(at: path) { data, error in
            guard let data else {
                result(nil, error)
                return
            }
            guard let png = Self.transparentLights(from: data) else {
                result(nil, URLError(.cannotDecodeContentData))
                return
            }
            result(png, nil)
        }
    }

    static func transparentLights(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let context = CGContext(
                  data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                  bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
              ),
              let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }

        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        for offset in stride(from: 0, to: context.bytesPerRow * image.height, by: 4) {
            // The valid source pixels are grayscale. Their premultiplied
            // intensity already includes the source alpha, so missing
            // observations stay transparent even if their palette is blue.
            let intensity = pixels[offset]
            pixels[offset + 1] = intensity
            pixels[offset + 2] = intensity
            pixels[offset + 3] = intensity
        }

        let png = NSMutableData()
        guard let lights = context.makeImage(),
              let destination = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, lights, nil)
        return CGImageDestinationFinalize(destination) ? png as Data : nil
    }
}
