import MapKit
import UIKit

@MainActor
final class MainMapCoordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
    private var parent: MapRepresentable
    private var lastKnownRegion: MKCoordinateRegion?
    private var outlineOverlay: CountryOutlineOverlay?
    private let backdrop = MapBackdropLayers()
    private let flights = FlightMapLayer()
    private let flightRoute = FlightRouteMapLayer()
    private let cables = CableMapLayer()
    private let hazards = HazardMapLayer()

    init(parent: MapRepresentable) {
        self.parent = parent
    }

    func update(_ mapView: MKMapView, parent: MapRepresentable) {
        self.parent = parent
        let routeFlightID = parent.flightRoute == nil ? nil : parent.selectedFlightID
        flights.update(on: mapView, snapshot: parent.flightMarkers, routeFlightID: routeFlightID)
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
        cables.update(on: mapView, cables: parent.cables, landingPoints: parent.landingPoints, selectedID: parent.selectedCableID)
        hazards.update(on: mapView, hazards: parent.hazards, tracks: parent.cycloneTracks)
        updateOutline(on: mapView, border: parent.outline)
        flightRoute.update(
            on: mapView, route: parent.flightRoute, aircraftCoordinate: flights.coordinate(for: routeFlightID)
        )

        if !MapRegionCalculator.matches(lastKnownRegion ?? mapView.region, parent.region) {
            lastKnownRegion = parent.region
            mapView.setRegion(parent.region, animated: false)
        }
    }

    func dismantle(_ mapView: MKMapView) {
        mapView.delegate = nil
        flightRoute.update(on: mapView, route: nil, aircraftCoordinate: nil)
        backdrop.stopEarthAtNight(on: mapView)
    }

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let renderer = flightRoute.renderer(for: overlay) { return renderer }
        if let renderer = backdrop.renderer(for: overlay) { return renderer }
        if let track = overlay as? CycloneTrackOverlay {
            return track.makeRenderer()
        }
        if let outline = overlay as? CountryOutlineOverlay {
            return outline.makeRenderer()
        }
        return cables.renderer(for: overlay) ?? MKOverlayRenderer(overlay: overlay)
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
        if let cableID = cables.nearestCableID(to: point, tolerance: 22 * mapPointsPerScreenPoint) {
            parent.selectCable(cableID)
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
        return flights.annotationView(on: mapView, for: annotation)
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
