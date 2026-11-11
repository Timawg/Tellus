//
//  MapRepresentable.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2024-07-25.
//

import Foundation
import MapKit
import SwiftUI

struct MapRepresentable: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    @Binding var selectedFlightID: String?
    let flightMarkers: FlightMarkerSnapshot
    var showsEarthAtNight = false
    var nightLightsDate: String?
    var viirsImageryDate: String?
    var auroraOverlay: AuroraOverlay?
    var showsPowerGrid = false
    var selectPowerAsset: (PowerGridAsset) -> Void = { _ in }
    var gpsJamOverlay: GPSJAMOverlay?
    var selectGPSJAMCell: (GPSJAMCell) -> Void = { _ in }
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

    func makeCoordinator() -> MainMapCoordinator {
        MainMapCoordinator(parent: self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.register(FlightMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "flight")
        mapView.register(LandingPointAnnotationView.self, forAnnotationViewWithReuseIdentifier: LandingPointAnnotationView.reuseIdentifier)
        mapView.register(HazardAnnotationView.self, forAnnotationViewWithReuseIdentifier: HazardAnnotationView.reuseIdentifier)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(MainMapCoordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        mapView.addGestureRecognizer(tap)
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
        context.coordinator.update(uiView, parent: self)
    }

    static func dismantleUIView(_ uiView: MKMapView, coordinator: MainMapCoordinator) {
        coordinator.dismantle(uiView)
    }
}
