import MapKit

@MainActor
final class CableMapLayer {
    private var cableOverlays: [String: CableOverlay] = [:]
    private var landingPointAnnotations: [String: LandingPointAnnotation] = [:]
    private var highlightedCableID: String?

    func update(on mapView: MKMapView, cables: [SubmarineCable], landingPoints: [CableLandingPoint], selectedID: String?) {
        let wanted = Set(cables.map(\.id))
        if wanted != Set(cableOverlays.keys) {
            let removed = cableOverlays.filter { !wanted.contains($0.key) }
            mapView.removeOverlays(Array(removed.values))
            removed.keys.forEach { cableOverlays[$0] = nil }
            let added = cables.filter { cableOverlays[$0.id] == nil }.map(CableOverlay.init(cable:))
            added.forEach { cableOverlays[$0.cableID] = $0 }
            mapView.addOverlays(added, level: .aboveRoads)
        }

        let wantedPoints = Set(landingPoints.map(\.id))
        if wantedPoints != Set(landingPointAnnotations.keys) {
            let removed = landingPointAnnotations.filter { !wantedPoints.contains($0.key) }
            mapView.removeAnnotations(Array(removed.values))
            removed.keys.forEach { landingPointAnnotations[$0] = nil }
            let added = landingPoints.filter { landingPointAnnotations[$0.id] == nil }.map(LandingPointAnnotation.init(point:))
            added.forEach { landingPointAnnotations[$0.id] = $0 }
            mapView.addAnnotations(added)
        }

        guard selectedID != highlightedCableID else { return }
        let previous = highlightedCableID
        highlightedCableID = selectedID
        for id in [previous, selectedID].compactMap({ $0 }) {
            guard let overlay = cableOverlays[id],
                  let renderer = mapView.renderer(for: overlay) as? MKMultiPolylineRenderer else { continue }
            style(renderer, for: overlay)
            renderer.setNeedsDisplay()
        }
    }

    func nearestCableID(to point: MKMapPoint, tolerance: Double) -> String? {
        cableOverlays.values
            .filter { $0.boundingMapRect.insetBy(dx: -tolerance, dy: -tolerance).contains(point) }
            .map { (id: $0.cableID, distance: $0.distance(to: point)) }
            .filter { $0.distance <= tolerance }
            .min { $0.distance < $1.distance }?.id
    }

    func renderer(for overlay: MKOverlay) -> MKOverlayRenderer? {
        guard let cable = overlay as? CableOverlay else { return nil }
        let renderer = MKMultiPolylineRenderer(multiPolyline: cable)
        style(renderer, for: cable)
        return renderer
    }

    private func style(_ renderer: MKMultiPolylineRenderer, for cable: CableOverlay) {
        let isSelected = cable.cableID == highlightedCableID
        renderer.strokeColor = cable.color.withAlphaComponent(isSelected ? 1 : 0.75)
        renderer.lineWidth = isSelected ? 4 : 1.5
        renderer.lineCap = .round
    }
}
