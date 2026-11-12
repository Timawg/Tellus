import MapKit
import UIKit

@MainActor
final class FlightRouteMapLayer {
    private var route: FlightRoute?
    private var overlay: MKGeodesicPolyline?
    private var renderer: MKPolylineRenderer?
    private var strokeEnd: CGFloat = 1
    private var animation: Task<Void, Never>?

    deinit {
        animation?.cancel()
    }

    func update(on mapView: MKMapView, route: FlightRoute?) {
        guard route != self.route else { return }
        animation?.cancel()
        animation = nil
        if let overlay { mapView.removeOverlay(overlay) }
        self.route = route
        overlay = nil
        renderer = nil

        guard let coordinates = route?.mapCoordinates else { return }
        let overlay = MKGeodesicPolyline(coordinates: coordinates, count: coordinates.count)
        self.overlay = overlay
        let shouldAnimate = !UIAccessibility.isReduceMotionEnabled
        strokeEnd = shouldAnimate ? 0 : 1
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
