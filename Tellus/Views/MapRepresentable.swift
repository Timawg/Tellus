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
    let regionWillChange: () -> Void
    let regionDidChange: (MKMapRect) -> Void

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapRepresentable

        init(parent: MapRepresentable) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            parent.regionWillChange()
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            parent.region = mapView.region
            parent.regionDidChange(mapView.visibleMapRect)
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let annotation = view.annotation as? T {
                parent.selectedAnnotation = annotation
                FlightAnnotationAnimator.animateSelect(view: view as? FlightMarkerAnnotationView)
            }
        }
        
        func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
            parent.selectedAnnotation = nil
            FlightAnnotationAnimator.animateDeselect(view: view as? FlightMarkerAnnotationView)
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
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

        annotationsToUpdate.forEach { newAnnotation in
            if let existingAnnotation = currentAnnotationsDict[newAnnotation.id] {
                UIView.animate(withDuration: 1) {
                    existingAnnotation.coordinate = newAnnotation.coordinate
                    
                    if let view = uiView.view(for: existingAnnotation), let degrees = newAnnotation.track {
                        view.transform = .init(rotationDegrees: CGFloat(degrees))
                    }
                }
            }
        }

        if selectedAnnotation == nil, let previousSelected = uiView.selectedAnnotations.first {
            uiView.deselectAnnotation(previousSelected, animated: false)
        }

        uiView.setRegion(region, animated: false)
    }

}


