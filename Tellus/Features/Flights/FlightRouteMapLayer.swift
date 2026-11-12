import MapKit
import UIKit

@MainActor
final class FlightRouteMapLayer {
    private var route: FlightRoute?
    private var aircraftCoordinate: CLLocationCoordinate2D?
    private var overlay: MKGeodesicPolyline?
    private var renderer: MKPolylineRenderer?
    private var strokeEnd: CGFloat = 1
    private var animation: Task<Void, Never>?

    deinit {
        animation?.cancel()
    }

    func update(on mapView: MKMapView, route: FlightRoute?, aircraftCoordinate: CLLocationCoordinate2D?) {
        guard route != self.route || aircraftCoordinate?.latitude != self.aircraftCoordinate?.latitude
                || aircraftCoordinate?.longitude != self.aircraftCoordinate?.longitude else { return }
        let startsRoute = route != self.route || overlay == nil
        if startsRoute {
            animation?.cancel()
            animation = nil
            strokeEnd = 1
        }
        if let overlay { mapView.removeOverlay(overlay) }
        self.route = route
        self.aircraftCoordinate = aircraftCoordinate
        overlay = nil
        renderer = nil

        guard let aircraftCoordinate,
              let coordinates = route?.mapCoordinates(through: aircraftCoordinate) else { return }
        let overlay = MKGeodesicPolyline(coordinates: coordinates, count: coordinates.count)
        self.overlay = overlay
        let shouldAnimate = startsRoute && !UIAccessibility.isReduceMotionEnabled
        if shouldAnimate { strokeEnd = 0 }
        mapView.addOverlay(overlay, level: .aboveLabels)
        if shouldAnimate { animateStroke() }
    }

    func renderer(for overlay: MKOverlay) -> MKPolylineRenderer? {
        guard let routeOverlay = self.overlay, routeOverlay === overlay else { return nil }
        let renderer = MKPolylineRenderer(polyline: routeOverlay)
        renderer.strokeColor = .systemCyan
        renderer.lineWidth = 3
        renderer.lineCap = .round
        renderer.lineJoin = .round
        renderer.strokeEnd = strokeEnd
        self.renderer = renderer
        return renderer
    }

    private func animateStroke() {
        animation = Task { [weak self] in
            let start = CACurrentMediaTime()
            let duration: CFTimeInterval = 0.8
            while !Task.isCancelled {
                let progress = CGFloat(min((CACurrentMediaTime() - start) / duration, 1))
                self?.strokeEnd = progress
                self?.renderer?.strokeEnd = progress
                if progress == 1 { return }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }
}
