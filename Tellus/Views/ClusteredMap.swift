//
//  ClusteredMap.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2024-07-25.
//

import Foundation
import MapKit
import SwiftUI

struct ClusteredMap: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    var annotations: [MKAnnotation]
    let didSelect: (any Identifiable) -> Void
    let visibleRegionChanged: (MKMapRect) -> Void

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: ClusteredMap

        init(parent: ClusteredMap) {
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            parent.region = mapView.region
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            parent.visibleRegionChanged(mapView.visibleMapRect)
        }
    
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            UIView.animate(withDuration: 0.2) {
                view.transform = .init(scaleX: 2, y: 2)
            }
            
            if let annotation = view.annotation as? FlightAnnotation {
                parent.didSelect(annotation)
            }
        }
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKClusterAnnotation {
                let identifier = "flight"
                var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                if view == nil {
                    view = FlightMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                }

                if let annotation = annotation as? FlightAnnotation, let degrees = annotation.track {
                    UIView.animate(withDuration: 0.2) {
                        view?.transform = .init(rotationAngle:(CGFloat(degrees) * .pi) / 180.0)
                    }
                }
                return view
            }

            let identifier = "flight"
            var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
            if view == nil {
                view = FlightMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)

            }
            if let annotation = annotation as? FlightAnnotation, let degrees = annotation.track {
                UIView.animate(withDuration: 0.2) {
                    view?.transform = .init(rotationAngle:(CGFloat(degrees) * .pi) / 180.0)
                }
            }
            return view
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
        mapView.setRegion(region, animated: false)
        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        uiView.removeAnnotations(uiView.annotations)
        uiView.addAnnotations(annotations)
        uiView.setRegion(region, animated: true)
    }
}


