import MapKit
import UIKit

@MainActor
final class MainMapCoordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
    private var parent: MapRepresentable
    private var lastKnownRegion: MKCoordinateRegion?
    private var drawnFlightSnapshot: FlightMarkerSnapshot?
    private var flightAnnotations: [String: FlightAnnotation] = [:]
    private var cableOverlays: [String: CableOverlay] = [:]
    private var landingPointAnnotations: [String: LandingPointAnnotation] = [:]
    private var highlightedCableID: String?
    private var hazardAnnotations: [String: HazardAnnotation] = [:]
    private var trackOverlays: [CycloneTrackOverlay] = []
    private var drawnTracks: [CycloneTrack] = []
    private var outlineOverlay: CountryOutlineOverlay?
    private let backdrop = MapBackdropLayers()

    init(parent: MapRepresentable) {
        self.parent = parent
    }

    func update(_ mapView: MKMapView, parent: MapRepresentable) {
        self.parent = parent
        updateFlights(on: mapView, snapshot: parent.flightMarkers)
        if parent.selectedFlightID == nil,
           let selected = mapView.selectedAnnotations.first(where: { $0 is FlightAnnotation }) {
            mapView.deselectAnnotation(selected, animated: false)
        }
        backdrop.update(
            on: mapView,
            viirsDate: parent.viirsImageryDate,
            showsEarthAtNight: parent.showsEarthAtNight,
            nightLightsDate: parent.nightLightsDate,
            showsPowerGrid: parent.showsPowerGrid,
            gpsJam: parent.gpsJamOverlay,
            aurora: parent.auroraOverlay
        )
        updateCables(on: mapView, cables: parent.cables, landingPoints: parent.landingPoints, selectedID: parent.selectedCableID)
        updateHazards(on: mapView, hazards: parent.hazards, tracks: parent.cycloneTracks)
        updateOutline(on: mapView, border: parent.outline)

        if !MapRegionCalculator.matches(lastKnownRegion ?? mapView.region, parent.region) {
            lastKnownRegion = parent.region
            mapView.setRegion(parent.region, animated: false)
        }
    }

    func dismantle(_ mapView: MKMapView) {
        mapView.delegate = nil
        backdrop.stopEarthAtNight(on: mapView)
    }

    private func updateFlights(on mapView: MKMapView, snapshot: FlightMarkerSnapshot) {
        guard drawnFlightSnapshot !== snapshot else { return }
        drawnFlightSnapshot = snapshot

        let wantedIDs = Set(snapshot.markers.map(\.id))
        let removed = flightAnnotations.values.filter { !wantedIDs.contains($0.id) }
        if !removed.isEmpty {
            removed.forEach { flightAnnotations[$0.id] = nil }
            mapView.removeAnnotations(removed)
        }

        var added: [FlightAnnotation] = []
        var changed: [(FlightAnnotation, FlightMarker)] = []
        for marker in snapshot.markers {
            if let annotation = flightAnnotations[marker.id] {
                if annotation.coordinate.latitude != marker.latitude ||
                    annotation.coordinate.longitude != marker.longitude ||
                    annotation.track != marker.track || annotation.source != marker.source {
                    changed.append((annotation, marker))
                }
            } else {
                let annotation = FlightAnnotation(marker: marker)
                flightAnnotations[marker.id] = annotation
                added.append(annotation)
            }
        }

        if !added.isEmpty { mapView.addAnnotations(added) }
        guard !changed.isEmpty else { return }

        UIView.animate(withDuration: 1) {
            for (annotation, marker) in changed {
                if annotation.coordinate.latitude != marker.latitude || annotation.coordinate.longitude != marker.longitude {
                    annotation.coordinate = marker.coordinate
                }
                annotation.track = marker.track
                let sourceChanged = annotation.source != marker.source
                annotation.source = marker.source
                if let view = mapView.view(for: annotation) as? FlightMarkerAnnotationView {
                    FlightAnnotationAnimator.applyTransform(to: view, selected: view.isSelected)
                    if sourceChanged { view.applySource() }
                }
            }
        }
    }

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let renderer = backdrop.renderer(for: overlay) { return renderer }
        if let track = overlay as? CycloneTrackOverlay {
            return track.makeRenderer()
        }
        if let outline = overlay as? CountryOutlineOverlay {
            return outline.makeRenderer()
        }
        guard let cable = overlay as? CableOverlay else {
            return MKOverlayRenderer(overlay: overlay)
        }
        let renderer = MKMultiPolylineRenderer(multiPolyline: cable)
        style(renderer, for: cable)
        return renderer
    }

    // MARK: Cables

    private func style(_ renderer: MKMultiPolylineRenderer, for cable: CableOverlay) {
        let isSelected = cable.cableID == highlightedCableID
        renderer.strokeColor = cable.color.withAlphaComponent(isSelected ? 1 : 0.75)
        renderer.lineWidth = isSelected ? 4 : 1.5
        renderer.lineCap = .round
    }

    /// MapKit handles annotation taps. Other taps check the overlays
    /// before selecting a country.
    @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended, let mapView = recognizer.view as? MKMapView,
              mapView.bounds.width > 0 else { return }
        let location = recognizer.location(in: mapView)
        // Taps on aircraft, hazards and landing points are handled by MapKit.
        if mapView.hitTest(location, with: nil)?.isAnnotationView == true { return }

        let coordinate = mapView.convert(location, toCoordinateFrom: mapView)
        let point = MKMapPoint(coordinate)
        let mapPointsPerScreenPoint = mapView.visibleMapRect.width / Double(mapView.bounds.width)
        let tolerance = 22 * mapPointsPerScreenPoint
        let nearest = cableOverlays.values
            .filter { $0.boundingMapRect.insetBy(dx: -tolerance, dy: -tolerance).contains(point) }
            .map { (id: $0.cableID, distance: $0.distance(to: point)) }
            .filter { $0.distance <= tolerance }
            .min { $0.distance < $1.distance }
        if let nearest {
            parent.selectCable(nearest.id)
        } else if let asset = backdrop.powerAsset(at: point, mapPointsPerScreenPoint: mapPointsPerScreenPoint) {
            parent.selectPowerAsset(asset)
        } else if let cell = parent.gpsJamOverlay?.cell(at: coordinate) {
            parent.selectGPSJAMCell(cell)
        } else {
            parent.tapCountry(coordinate)
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    /// Waits for MapKit's double tap to fail, so double-tapping to zoom
    /// doesn't also select the country under the finger.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf other: UIGestureRecognizer) -> Bool {
        (other as? UITapGestureRecognizer)?.numberOfTapsRequired == 2
    }

    private func updateCables(on mapView: MKMapView, cables: [SubmarineCable], landingPoints: [CableLandingPoint], selectedID: String?) {
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

    // MARK: Country outline

    private func updateOutline(on mapView: MKMapView, border: CountryBorder?) {
        guard outlineOverlay?.cca3 != border?.cca3 else { return }
        if let outlineOverlay {
            mapView.removeOverlay(outlineOverlay)
        }
        outlineOverlay = border.map(CountryOutlineOverlay.init(border:))
        if let outlineOverlay {
            // Keep it above the imagery and grid, and under cables and tracks.
            if let topOverlay = backdrop.topOverlay {
                mapView.insertOverlay(outlineOverlay, above: topOverlay)
            } else {
                mapView.insertOverlay(outlineOverlay, at: 0, level: .aboveRoads)
            }
        }
    }

    // MARK: Hazards

    private func updateHazards(on mapView: MKMapView, hazards: [NaturalHazard], tracks: [CycloneTrack]) {
        let wanted = Dictionary(hazards.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Gone, or changed (a cyclone moves, an alert level rises).
        let stale = hazardAnnotations.filter { id, annotation in wanted[id] != annotation.hazard }
        if !stale.isEmpty {
            mapView.removeAnnotations(Array(stale.values))
            stale.keys.forEach { hazardAnnotations[$0] = nil }
        }
        let added = wanted.values.filter { hazardAnnotations[$0.id] == nil }.map(HazardAnnotation.init(hazard:))
        if !added.isEmpty {
            added.forEach { hazardAnnotations[$0.hazard.id] = $0 }
            mapView.addAnnotations(added)
        }

        guard tracks != drawnTracks else { return }
        mapView.removeOverlays(trackOverlays)
        trackOverlays = tracks.flatMap { track in
            [
                track.observed.isEmpty ? nil : CycloneTrackOverlay(track: track, forecast: false),
                track.forecast.isEmpty ? nil : CycloneTrackOverlay(track: track, forecast: true),
            ].compactMap { $0 }
        }
        drawnTracks = tracks
        mapView.addOverlays(trackOverlays, level: .aboveRoads)
    }

    func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
        parent.regionWillChange()
    }

    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        let region = mapView.region
        lastKnownRegion = region
        if !MapRegionCalculator.matches(parent.region, region) {
            parent.region = region
        }
        parent.regionDidChange(mapView.visibleMapRect)
    }

    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        if let annotation = view.annotation as? HazardAnnotation {
            // Shown in a sheet; deselect so the same pin can be tapped again.
            mapView.deselectAnnotation(annotation, animated: false)
            parent.selectHazard(annotation.hazard.id)
            return
        }
        if let annotation = view.annotation as? FlightAnnotation {
            parent.selectedFlightID = annotation.id
            FlightAnnotationAnimator.animateSelect(view: view as? FlightMarkerAnnotationView)
        }
    }

    func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
        guard let annotation = view.annotation as? FlightAnnotation else { return }
        if parent.selectedFlightID == annotation.id { parent.selectedFlightID = nil }
        FlightAnnotationAnimator.animateDeselect(view: view as? FlightMarkerAnnotationView)
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if annotation is LandingPointAnnotation {
            return mapView.dequeueReusableAnnotationView(withIdentifier: LandingPointAnnotationView.reuseIdentifier, for: annotation)
        }
        if annotation is HazardAnnotation {
            return mapView.dequeueReusableAnnotationView(withIdentifier: HazardAnnotationView.reuseIdentifier, for: annotation)
        }
        guard annotation is FlightAnnotation,
              let view = mapView.dequeueReusableAnnotationView(withIdentifier: "flight", for: annotation)
                as? FlightMarkerAnnotationView else { return nil }
        FlightAnnotationAnimator.applyTransform(to: view, selected: view.isSelected)
        return view
    }
}

private extension UIView {
    /// This view or one of its ancestors is an annotation view.
    var isAnnotationView: Bool {
        var view: UIView? = self
        while let current = view {
            if current is MKAnnotationView { return true }
            view = current.superview
        }
        return false
    }
}
