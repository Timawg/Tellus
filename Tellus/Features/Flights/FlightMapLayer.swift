import MapKit
import UIKit

@MainActor
final class FlightMapLayer {
    private var drawnFlightSnapshot: FlightMarkerSnapshot?
    private var flightAnnotations: [String: FlightAnnotation] = [:]

    func update(on mapView: MKMapView, snapshot: FlightMarkerSnapshot) {
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

    func annotationView(on mapView: MKMapView, for annotation: MKAnnotation) -> MKAnnotationView? {
        guard annotation is FlightAnnotation,
              let view = mapView.dequeueReusableAnnotationView(withIdentifier: "flight", for: annotation)
                as? FlightMarkerAnnotationView else { return nil }
        FlightAnnotationAnimator.applyTransform(to: view, selected: view.isSelected)
        return view
    }
}
