import MapKit

@MainActor
final class HazardMapLayer {
    private var hazardAnnotations: [String: HazardAnnotation] = [:]
    private var trackOverlays: [CycloneTrackOverlay] = []
    private var drawnTracks: [CycloneTrack] = []

    func update(on mapView: MKMapView, hazards: [NaturalHazard], tracks: [CycloneTrack]) {
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
}
