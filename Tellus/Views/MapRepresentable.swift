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
    /// Undersea cables to draw; empty when the layer is off.
    var cables: [SubmarineCable] = []
    var landingPoints: [CableLandingPoint] = []
    /// Drawn thicker and brighter than the others.
    var selectedCableID: String?
    /// Called with the cable nearest a tap, or nil for a tap away from cables.
    var selectCable: (String?) -> Void = { _ in }
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

        init(parent: MapRepresentable) {
            self.parent = parent
        }

        // MARK: Cables

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let track = overlay as? CycloneTrackOverlay {
                return track.makeRenderer()
            }
            guard let cable = overlay as? CableOverlay else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKMultiPolylineRenderer(multiPolyline: cable)
            style(renderer, for: cable)
            return renderer
        }

        func style(_ renderer: MKMultiPolylineRenderer, for cable: CableOverlay) {
            let isSelected = cable.cableID == highlightedCableID
            renderer.strokeColor = cable.color.withAlphaComponent(isSelected ? 1 : 0.75)
            renderer.lineWidth = isSelected ? 4 : 1.5
            renderer.lineCap = .round
        }

        /// MapKit doesn't report taps on overlays, so find the nearest cable
        /// within about 22 points of the tap.
        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let mapView = recognizer.view as? MKMapView else { return }
            let location = recognizer.location(in: mapView)
            // Taps on aircraft, hazards and landing points are handled by MapKit.
            if mapView.hitTest(location, with: nil)?.isAnnotationView == true { return }
            guard !cableOverlays.isEmpty, mapView.bounds.width > 0 else { return }

            let point = MKMapPoint(mapView.convert(location, toCoordinateFrom: mapView))
            let tolerance = 22 * mapView.visibleMapRect.width / Double(mapView.bounds.width)
            let nearest = cableOverlays.values
                .filter { $0.boundingMapRect.insetBy(dx: -tolerance, dy: -tolerance).contains(point) }
                .map { (id: $0.cableID, distance: $0.distance(to: point)) }
                .filter { $0.distance <= tolerance }
                .min { $0.distance < $1.distance }
            parent.selectCable(nearest?.id)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
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
            existingAnnotation.coordinate.longitude != annotation.coordinate.longitude
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

                    if let view = uiView.view(for: existingAnnotation), let degrees = newAnnotation.track {
                        view.transform = .init(rotationDegrees: CGFloat(degrees))
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
        context.coordinator.updateCables(on: uiView, cables: cables, landingPoints: landingPoints, selectedID: selectedCableID)
        context.coordinator.updateHazards(on: uiView, hazards: hazards, tracks: cycloneTracks)

        uiView.setRegion(region, animated: false)
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
