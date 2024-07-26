//
//  ClusteredMap.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2024-07-25.
//

import Foundation
import MapKit
import SwiftUI

struct MapRepresentable: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    var annotations: [MKAnnotation]
    let didSelect: (any Identifiable) -> Void
    let visibleRegionChanged: (MKMapRect) -> Void

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapRepresentable

        init(parent: MapRepresentable) {
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            parent.region = mapView.region
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            parent.visibleRegionChanged(mapView.visibleMapRect)
        }
    
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let annotation = view.annotation as? FlightAnnotation {
                parent.didSelect(annotation)
            }
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
                annotationView.transform = .init(rotationAngle: -1.5708).rotated(by: CGFloat(degrees) * .pi / 180.0)
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
        mapView.showsTraffic = true
        mapView.showsUserLocation = true
        mapView.isZoomEnabled = true
        mapView.isScrollEnabled = true
        mapView.isRotateEnabled = true
        mapView.isPitchEnabled = true
        mapView.mapType = .hybridFlyover
        mapView.setRegion(region, animated: false)
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
                    
                    if let view = uiView.view(for: newAnnotation), let degrees = newAnnotation.track {
                        view.transform = .init(rotationAngle: CGFloat(degrees) * .pi / 180.0)
                    }
                }
            }
        }

        uiView.setRegion(region, animated: false)
    }

}


