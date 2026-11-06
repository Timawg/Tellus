//
//  MapRepresentable.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2024-07-25.
//

import Foundation
import MapKit
import SwiftUI

struct MapRepresentable<T: MKAnnotation>: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    @Binding var selectedAnnotation: T?
    var annotations: [MKAnnotation]
    var showsEarthAtNight = false
    var nightLightsDate: String?
    var viirsImageryDate: String?
    var showsPowerGrid = false
    var selectPowerAsset: (PowerGridAsset) -> Void = { _ in }
    /// Undersea cables to draw; empty when the layer is off.
    var cables: [SubmarineCable] = []
    var landingPoints: [CableLandingPoint] = []
    /// Drawn thicker and brighter than the others.
    var selectedCableID: String?
    /// Called with the cable nearest a tap, or nil for a tap away from cables.
    var selectCable: (String?) -> Void = { _ in }
    /// Called with the coordinate of a tap that hit no aircraft, pin or
    /// cable, to select the country there.
    var tapCountry: (CLLocationCoordinate2D) -> Void = { _ in }
    /// The selected country, outlined.
    var outline: CountryBorder?
    /// Natural hazards and cyclone tracks to draw; empty when the layer is off.
    var hazards: [NaturalHazard] = []
    var cycloneTracks: [CycloneTrack] = []
    /// Called with the id of a tapped hazard.
    var selectHazard: (String) -> Void = { _ in }
    let regionWillChange: () -> Void
    let regionDidChange: (MKMapRect) -> Void

    class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: MapRepresentable
        var cableOverlays: [String: CableOverlay] = [:]
        var landingPointAnnotations: [String: LandingPointAnnotation] = [:]
        var highlightedCableID: String?
        var hazardAnnotations: [String: HazardAnnotation] = [:]
        var trackOverlays: [CycloneTrackOverlay] = []
        var drawnTracks: [CycloneTrack] = []
        var outlineOverlay: CountryOutlineOverlay?
        private var viirsOverlay: MKTileOverlay?
        private var viirsDate: String?
        private var nightOverlay: NightOverlay?
        private var nightLightsOverlay: MKTileOverlay?
        private var nightLightsDate: String?
        private var nightTimer: Timer?
        private var powerGridOverlay: PowerGridOverlay?

        init(parent: MapRepresentable) {
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tiles = overlay as? MKTileOverlay {
                let renderer = MKTileOverlayRenderer(tileOverlay: tiles)
                if tiles === viirsOverlay {
                    renderer.alpha = 0.85
                }
                return renderer
            }
            if let night = overlay as? NightOverlay {
                return NightOverlayRenderer(night: night)
            }
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

        // MARK: Satellite and night layers

        func updateVIIRSImagery(on mapView: MKMapView, date: String?) {
            guard date != viirsDate else { return }
            if let viirsOverlay { mapView.removeOverlay(viirsOverlay) }
            viirsOverlay = nil
            viirsDate = date
            guard let date else { return }

            let tiles = MKTileOverlay(urlTemplate: VIIRSImageryService.tileTemplate(for: .trueColour, date: date))
            tiles.maximumZ = VIIRSImageryService.Product.trueColour.maximumZoom
            tiles.canReplaceMapContent = false
            viirsOverlay = tiles
            mapView.insertOverlay(tiles, at: 0, level: .aboveRoads)
        }

        func updatePowerGrid(on mapView: MKMapView, enabled: Bool) {
            if enabled {
                guard powerGridOverlay == nil else { return }
                let grid = PowerGridOverlay()
                powerGridOverlay = grid
                if let imagery = (nightLightsOverlay as MKOverlay?) ?? (nightOverlay as MKOverlay?) ?? viirsOverlay {
                    mapView.insertOverlay(grid, above: imagery)
                } else {
                    mapView.insertOverlay(grid, at: 0, level: .aboveRoads)
                }
            } else if let powerGridOverlay {
                mapView.removeOverlay(powerGridOverlay)
                self.powerGridOverlay = nil
            }
        }

        @MainActor
        func updateEarthAtNight(on mapView: MKMapView, enabled: Bool, lightsDate: String?) {
            guard enabled else {
                stopEarthAtNight(on: mapView)
                return
            }
            if nightTimer == nil {
                refreshNight(on: mapView)
                let timer = Timer(timeInterval: 60, repeats: true) { [weak self, weak mapView] _ in
                    MainActor.assumeIsolated {
                        guard let mapView else { return }
                        self?.refreshNight(on: mapView)
                    }
                }
                nightTimer = timer
                RunLoop.main.add(timer, forMode: .common)
            }
            updateNightLights(on: mapView, date: lightsDate)
        }

        private func updateNightLights(on mapView: MKMapView, date: String?) {
            guard date != nightLightsDate else { return }
            if let nightLightsOverlay { mapView.removeOverlay(nightLightsOverlay) }
            nightLightsOverlay = nil
            nightLightsDate = date
            guard let date, let nightOverlay else { return }

            let tiles = NightLightsTileOverlay(urlTemplate: VIIRSImageryService.tileTemplate(for: .nightLights, date: date))
            tiles.maximumZ = VIIRSImageryService.Product.nightLights.maximumZoom
            tiles.canReplaceMapContent = false
            nightLightsOverlay = tiles
            mapView.insertOverlay(tiles, above: nightOverlay)
        }

        @MainActor
        func stopEarthAtNight(on mapView: MKMapView) {
            nightTimer?.invalidate()
            nightTimer = nil
            updateNightLights(on: mapView, date: nil)
            if let nightOverlay {
                mapView.removeOverlay(nightOverlay)
                self.nightOverlay = nil
            }
        }

        @MainActor
        private func refreshNight(on mapView: MKMapView) {
            let next = NightOverlay(date: Date())
            if let nightOverlay { mapView.removeOverlay(nightOverlay) }
            nightOverlay = next
            mapView.insertOverlay(next, at: viirsOverlay == nil ? 0 : 1, level: .aboveRoads)
        }

        // MARK: Cables

        func style(_ renderer: MKMultiPolylineRenderer, for cable: CableOverlay) {
            let isSelected = cable.cableID == highlightedCableID
            renderer.strokeColor = cable.color.withAlphaComponent(isSelected ? 1 : 0.75)
            renderer.lineWidth = isSelected ? 4 : 1.5
            renderer.lineCap = .round
        }

        /// MapKit doesn't report taps on overlays, so find the nearest cable
        /// within about 22 points of the tap; away from cables, the tap
        /// selects the country under it.
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
            } else if let asset = powerGridOverlay?.asset(at: point, mapPointsPerScreenPoint: mapPointsPerScreenPoint) {
                parent.selectPowerAsset(asset)
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

        func updateCables(on mapView: MKMapView, cables: [SubmarineCable], landingPoints: [CableLandingPoint], selectedID: String?) {
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

        func updateOutline(on mapView: MKMapView, border: CountryBorder?) {
            guard outlineOverlay?.cca3 != border?.cca3 else { return }
            if let outlineOverlay {
                mapView.removeOverlay(outlineOverlay)
            }
            outlineOverlay = border.map(CountryOutlineOverlay.init(border:))
            if let outlineOverlay {
                // Keep it above the imagery and grid, and under cables and tracks.
                if let backdrop = (powerGridOverlay as MKOverlay?) ?? (nightLightsOverlay as MKOverlay?)
                    ?? (nightOverlay as MKOverlay?) ?? viirsOverlay {
                    mapView.insertOverlay(outlineOverlay, above: backdrop)
                } else {
                    mapView.insertOverlay(outlineOverlay, at: 0, level: .aboveRoads)
                }
            }
        }

        // MARK: Hazards

        func updateHazards(on mapView: MKMapView, hazards: [NaturalHazard], tracks: [CycloneTrack]) {
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
            parent.region = mapView.region
            parent.regionDidChange(mapView.visibleMapRect)
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let annotation = view.annotation as? HazardAnnotation {
                // Shown in a sheet; deselect so the same pin can be tapped again.
                mapView.deselectAnnotation(annotation, animated: false)
                parent.selectHazard(annotation.hazard.id)
                return
            }
            if let annotation = view.annotation as? T {
                parent.selectedAnnotation = annotation
                FlightAnnotationAnimator.animateSelect(view: view as? FlightMarkerAnnotationView)
            }
        }
        
        func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
            guard view.annotation is T else { return }
            parent.selectedAnnotation = nil
            FlightAnnotationAnimator.animateDeselect(view: view as? FlightMarkerAnnotationView)
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is LandingPointAnnotation {
                return mapView.dequeueReusableAnnotationView(withIdentifier: LandingPointAnnotationView.reuseIdentifier, for: annotation)
            }
            if annotation is HazardAnnotation {
                return mapView.dequeueReusableAnnotationView(withIdentifier: HazardAnnotationView.reuseIdentifier, for: annotation)
            }
            let identifier = "flight"
            let annotationView: FlightMarkerAnnotationView = {
                if let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? FlightMarkerAnnotationView {
                    return view
                } else {
                    return FlightMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                }
            }()
            if let annotation = annotation as? FlightAnnotation, let degrees = annotation.track {
                annotationView.transform = annotationView.transform.rotate(to: CGFloat(degrees))
            }
            return annotationView
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.register(FlightMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "flight")
        mapView.register(LandingPointAnnotationView.self, forAnnotationViewWithReuseIdentifier: LandingPointAnnotationView.reuseIdentifier)
        mapView.register(HazardAnnotationView.self, forAnnotationViewWithReuseIdentifier: HazardAnnotationView.reuseIdentifier)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        mapView.addGestureRecognizer(tap)
        mapView.addAnnotations(annotations)
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.isZoomEnabled = true
        mapView.isScrollEnabled = true
        mapView.isRotateEnabled = true
        mapView.isPitchEnabled = true
        mapView.setRegion(region, animated: false)
        mapView.overrideUserInterfaceStyle = .dark
        return mapView
    }
    func updateUIView(_ uiView: MKMapView, context: Context) {

        let currentAnnotations = uiView.annotations.compactMap { $0 as? FlightAnnotation }
        let newAnnotations = annotations.compactMap { $0 as? FlightAnnotation }

        let currentAnnotationsDict = Dictionary(uniqueKeysWithValues: currentAnnotations.map { ($0.id, $0) })
        let newAnnotationsDict = Dictionary(uniqueKeysWithValues: newAnnotations.map { ($0.id, $0) })

        let annotationsToRemove = currentAnnotations.filter { annotation in
            return newAnnotationsDict[annotation.id] == nil
        }

        let annotationsToAdd = newAnnotations.filter { annotation in
            return currentAnnotationsDict[annotation.id] == nil
        }

        let annotationsToUpdate = newAnnotations.filter { annotation in
            guard let existingAnnotation = currentAnnotationsDict[annotation.id] else {
                return false
            }
            return existingAnnotation.coordinate.latitude != annotation.coordinate.latitude ||
            existingAnnotation.coordinate.longitude != annotation.coordinate.longitude ||
            existingAnnotation.source != annotation.source
        }

        uiView.removeAnnotations(annotationsToRemove)
        uiView.addAnnotations(annotationsToAdd)

        // One animation for every moved aircraft, rather than one each.
        if !annotationsToUpdate.isEmpty {
            UIView.animate(withDuration: 1) {
                annotationsToUpdate.forEach { newAnnotation in
                    guard let existingAnnotation = currentAnnotationsDict[newAnnotation.id] else {
                        return
                    }
                    existingAnnotation.coordinate = newAnnotation.coordinate
                    let view = uiView.view(for: existingAnnotation)

                    if let view, let degrees = newAnnotation.track {
                        view.transform = .init(rotationDegrees: CGFloat(degrees))
                    }
                    // adsb.lol's military list can take over an aircraft
                    // OpenSky reported, which recolours its marker.
                    if existingAnnotation.source != newAnnotation.source {
                        existingAnnotation.source = newAnnotation.source
                        (view as? FlightMarkerAnnotationView)?.applySource()
                    }
                }
            }
        }

        // Only flights are deselected from here; a landing point's callout
        // stays open until the user dismisses it.
        if selectedAnnotation == nil, let previousSelected = uiView.selectedAnnotations.first(where: { $0 is FlightAnnotation }) {
            uiView.deselectAnnotation(previousSelected, animated: false)
        }

        context.coordinator.parent = self
        context.coordinator.updateVIIRSImagery(on: uiView, date: viirsImageryDate)
        context.coordinator.updateEarthAtNight(on: uiView, enabled: showsEarthAtNight, lightsDate: nightLightsDate)
        context.coordinator.updatePowerGrid(on: uiView, enabled: showsPowerGrid)
        context.coordinator.updateCables(on: uiView, cables: cables, landingPoints: landingPoints, selectedID: selectedCableID)
        context.coordinator.updateHazards(on: uiView, hazards: hazards, tracks: cycloneTracks)
        context.coordinator.updateOutline(on: uiView, border: outline)

        uiView.setRegion(region, animated: false)
    }

    static func dismantleUIView(_ uiView: MKMapView, coordinator: Coordinator) {
        coordinator.stopEarthAtNight(on: uiView)
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
