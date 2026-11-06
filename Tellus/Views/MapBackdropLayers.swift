import MapKit

@MainActor
final class MapBackdropLayers {
    private var viirsOverlay: MKTileOverlay?
    private var viirsDate: String?
    private var nightOverlay: NightOverlay?
    private var nightLightsOverlay: MKTileOverlay?
    private var nightLightsDate: String?
    private var nightTimer: Timer?
    private var gpsJamOverlay: GPSJAMOverlay?
    private var powerGridOverlay: PowerGridOverlay?

    var topOverlay: MKOverlay? {
        (powerGridOverlay as MKOverlay?) ?? (gpsJamOverlay as MKOverlay?) ?? imageryOverlay
    }

    private var imageryOverlay: MKOverlay? {
        (nightLightsOverlay as MKOverlay?) ?? (nightOverlay as MKOverlay?) ?? viirsOverlay
    }

    func update(
        on mapView: MKMapView, viirsDate: String?, showsEarthAtNight: Bool,
        nightLightsDate: String?, showsPowerGrid: Bool, gpsJam: GPSJAMOverlay?
    ) {
        updateVIIRSImagery(on: mapView, date: viirsDate)
        updateEarthAtNight(on: mapView, enabled: showsEarthAtNight, lightsDate: nightLightsDate)
        updateGPSJAM(on: mapView, overlay: gpsJam)
        updatePowerGrid(on: mapView, enabled: showsPowerGrid)
    }

    func renderer(for overlay: MKOverlay) -> MKOverlayRenderer? {
        if overlay is GPSJAMOverlay { return GPSJAMOverlayRenderer(overlay: overlay) }
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
        return nil
    }

    func powerAsset(at point: MKMapPoint, mapPointsPerScreenPoint: Double) -> PowerGridAsset? {
        powerGridOverlay?.asset(at: point, mapPointsPerScreenPoint: mapPointsPerScreenPoint)
    }

    private func updateVIIRSImagery(on mapView: MKMapView, date: String?) {
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

    private func updateGPSJAM(on mapView: MKMapView, overlay: GPSJAMOverlay?) {
        guard gpsJamOverlay !== overlay else { return }
        if let gpsJamOverlay { mapView.removeOverlay(gpsJamOverlay) }
        gpsJamOverlay = overlay
        guard let overlay else { return }
        if let powerGridOverlay {
            mapView.insertOverlay(overlay, below: powerGridOverlay)
        } else if let imagery = imageryOverlay {
            mapView.insertOverlay(overlay, above: imagery)
        } else {
            mapView.insertOverlay(overlay, at: 0, level: .aboveRoads)
        }
    }

    private func updatePowerGrid(on mapView: MKMapView, enabled: Bool) {
        if enabled {
            guard powerGridOverlay == nil else { return }
            let grid = PowerGridOverlay()
            powerGridOverlay = grid
            if let backdrop = (gpsJamOverlay as MKOverlay?) ?? imageryOverlay {
                mapView.insertOverlay(grid, above: backdrop)
            } else {
                mapView.insertOverlay(grid, at: 0, level: .aboveRoads)
            }
        } else if let powerGridOverlay {
            mapView.removeOverlay(powerGridOverlay)
            self.powerGridOverlay = nil
        }
    }

    private func updateEarthAtNight(on mapView: MKMapView, enabled: Bool, lightsDate: String?) {
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

    func stopEarthAtNight(on mapView: MKMapView) {
        nightTimer?.invalidate()
        nightTimer = nil
        updateNightLights(on: mapView, date: nil)
        if let nightOverlay {
            mapView.removeOverlay(nightOverlay)
            self.nightOverlay = nil
        }
    }

    private func refreshNight(on mapView: MKMapView) {
        let next = NightOverlay(date: Date())
        if let nightOverlay { mapView.removeOverlay(nightOverlay) }
        nightOverlay = next
        mapView.insertOverlay(next, at: viirsOverlay == nil ? 0 : 1, level: .aboveRoads)
    }
}
