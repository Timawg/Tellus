//
//  MainMapViewModel.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2024-07-23.
//

import Foundation
import UIKit
import MapKit

@MainActor
@Observable
final class MainMapViewModel {

    private let services: MainMapServices
    private let preferences: MapPreferencesStore
    let flights: LiveFlightsModel
    let countryGuide: CountryGuideModel
    let cableLayer: CableLayerModel
    let hazardLayer: HazardLayerModel

    init(
        services: MainMapServices,
        preferences: MapPreferencesStore,
        flights: LiveFlightsModel,
        countryGuide: CountryGuideModel,
        cableLayer: CableLayerModel,
        hazardLayer: HazardLayerModel
    ) {
        self.services = services
        self.preferences = preferences
        self.nationality = preferences.nationality
        self.flights = flights
        self.countryGuide = countryGuide
        self.cableLayer = cableLayer
        self.hazardLayer = hazardLayer
        self.showsPowerGrid = preferences[.powerGrid]
        self.showsEarthAtNight = preferences[.earthAtNight]
        self.showsAurora = preferences[.aurora]
        self.showsGPSJAM = preferences[.gpsJam]
        self.showsVIIRSImagery = preferences[.viirsImagery]
        countryGuide.updateSelection(destination: nil, passport: nationality)
    }

    // MARK: Country selection and map region

    @ObservationIgnored private var visibleRect: MKMapRect = .world
    var region: MKCoordinateRegion = .init(.world)
    var countries: [Country] = []
    var current: Country? {
        didSet { countryGuide.updateSelection(destination: current, passport: nationality) }
    }
    var loadingError: String?

    func retrieveCountries() async {
        do {
            // Alphabetical, so the pickers are easy to scan.
            let loaded = try await services.countriesService.getAllCountries()
            guard !Task.isCancelled else { return }
            countries = loaded.sorted {
                ($0.name?.common ?? "").localizedStandardCompare($1.name?.common ?? "") == .orderedAscending
            }
            loadingError = nil
            selectRandomCountry()
        } catch {
            guard !Task.isCancelled else { return }
            loadingError = "Could not load countries. Please check your connection and try again."
        }
    }

    private func findRegion(by name: String) async -> MKCoordinateRegion? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = name
        let results = try? await MKLocalSearch(request: request).start()
        return results?.boundingRegion
    }

    func selectRandomCountry() {
        guard let randomCountry = countries.randomElement() else {
            return
        }
        current = randomCountry
    }

    /// Countries sharing a border with `country`, by name.
    func neighbours(of country: Country) -> [Country] {
        let codes = Set(country.borders ?? [])
        return countries.filter { $0.cca3.map(codes.contains) ?? false }
    }

    /// The selected country's outline; nil when it isn't in the bundled
    /// borders (a few tiny territories).
    var selectedBorder: CountryBorder?
    @ObservationIgnored private var borders: [String: CountryBorder]?
    @ObservationIgnored private var bordersTask: Task<[String: CountryBorder], Never>?

    /// Selects the country under a tap on the map. Taps on the sea, or on
    /// the selected country, do nothing.
    func selectCountry(at coordinate: CLLocationCoordinate2D) async {
        let borders = await loadBorders()
        guard let code = CountryBorders.country(at: coordinate, in: borders),
              code != current?.cca3,
              let country = countries.first(where: { $0.cca3 == code }) else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        current = country
    }

    /// Decodes the bundled borders once, off the main thread.
    private func loadBorders() async -> [String: CountryBorder] {
        if let borders { return borders }
        let task = bordersTask ?? Task.detached(priority: .userInitiated) {
            (try? CountryBorders.load()) ?? [:]
        }
        bordersTask = task
        let loaded = await task.value
        borders = loaded
        bordersTask = nil
        return loaded
    }

    /// Outlines the selected country and zooms to fit it between the
    /// country card and the bottom buttons. Countries without an outline fall
    /// back to a zoom based on their area.
    private func updateRegion() async {
        guard let country = current else {
            selectedBorder = nil
            return
        }
        let border = await loadBorders()[country.cca3 ?? ""]
        guard !Task.isCancelled, current?.id == country.id else { return }
        selectedBorder = border
        if let border {
            region = MapRegionCalculator.fitting(border, in: visibleRect)
        } else if let areaRegion = MapRegionCalculator.region(for: country) {
            region = areaRegion
        } else if let name = country.name?.common,
                  let searchRegion = await findRegion(by: name),
                  !Task.isCancelled, current?.id == country.id {
            region = searchRegion
        }
    }

    var nationality: Country? {
        didSet {
            preferences.nationality = nationality
            countryGuide.updateSelection(destination: current, passport: nationality)
        }
    }

    func refreshDestination() async {
        guard !Task.isCancelled else { return }
        async let map: Void = updateRegion()
        async let guide: Void = countryGuide.refreshDestination(current, countries: countries)
        _ = await (map, guide)
    }

    // MARK: Map layers

    var showsPowerGrid: Bool {
        didSet { preferences[.powerGrid] = showsPowerGrid }
    }

    var showsEarthAtNight: Bool {
        didSet { preferences[.earthAtNight] = showsEarthAtNight }
    }

    var showsAurora: Bool {
        didSet { preferences[.aurora] = showsAurora }
    }

    func loadAuroraForecast() async throws -> AuroraOverlay {
        try await services.auroraService.getForecast()
    }

    var showsGPSJAM: Bool {
        didSet { preferences[.gpsJam] = showsGPSJAM }
    }

    func loadGPSJAMOverlay(for day: Date?) async throws -> GPSJAMOverlay {
        try await services.gpsJamService.getOverlay(for: day)
    }

    var showsVIIRSImagery: Bool {
        didSet { preferences[.viirsImagery] = showsVIIRSImagery }
    }

    func loadVIIRSImageryDates(for product: VIIRSImageryService.Product) async throws -> [String] {
        try await services.viirsImageryService.getAvailableDates(for: product)
    }

    func updateViewport(_ rect: MKMapRect) {
        visibleRect = rect
        flights.updateViewport(rect)
    }
}
