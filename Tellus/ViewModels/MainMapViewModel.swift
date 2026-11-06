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

    init(services: MainMapServices, preferences: MapPreferencesStore) {
        self.services = services
        self.preferences = preferences
        self.nationality = preferences.nationality
        self.showsFlights = preferences[.flights]
        self.showsCables = preferences[.cables]
        self.showsHazards = preferences[.hazards]
        self.showsPowerGrid = preferences[.powerGrid]
        self.showsEarthAtNight = preferences[.earthAtNight]
        self.showsVIIRSImagery = preferences[.viirsImagery]
    }

    // MARK: Country selection and map region

    @ObservationIgnored private var visibleRect: MKMapRect = .world
    var region: MKCoordinateRegion = .init(.world)
    var countries: [Country] = []
    var current: Country?
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

    // MARK: Destination and passport information

    var nationality: Country? {
        didSet { preferences.nationality = nationality }
    }
    var advisoryStatus: AdvisoryStatus?
    /// The advisory's entry, health, laws and climate advice and emergency
    /// numbers, without the parts that only apply to Canadians.
    var destinationGuide: DestinationGuide?
    var isLoadingDestinationGuide = false
    var admissoryStatus: AdmissoryStatus?

    /// Weather at the selected country's capital.
    var destinationWeather: DestinationWeather?

    /// What one unit of the home currency buys in each of the selected
    /// country's currencies. Empty when they share a currency.
    var exchangeRates: [ExchangeRate] = []

    /// The currency rates are shown from: the passport country's, else the
    /// device's region's, else US dollars.
    var homeCurrency: String {
        nationality?.currencies?.keys.sorted().first
            ?? Locale.current.currency?.identifier
            ?? "USD"
    }

    private func updateWeather() async {
        guard let country = current else { return }
        let weather = try? await services.weatherService.getWeather(for: country)
        // Another country may have been chosen while loading.
        guard !Task.isCancelled, current?.id == country.id else { return }
        destinationWeather = weather
    }

    /// Dated events from Wikipedia's "<year> in <country>" article.
    var recentEvents: RecentEvents?
    /// Current GDACS orange and red alerts for the selected country.
    var disasterAlerts: [DisasterAlert] = []

    func loadCountryProfile(countryCode: String) async throws -> [CountryIndicatorObservation] {
        try await services.countryProfileService.getProfile(countryCode: countryCode)
    }

    private func updateRecentEvents() async {
        guard let country = current else { return }
        let events = try? await services.recentEventsService.getRecentEvents(for: country)
        guard !Task.isCancelled, current?.id == country.id else { return }
        recentEvents = events
    }

    private func updateDisasterAlerts() async {
        guard let country = current, let code = country.cca2 else { return }
        let alerts = (try? await services.disasterAlertService.getAlerts(countryCode: code)) ?? []
        guard !Task.isCancelled, current?.id == country.id else { return }
        disasterAlerts = alerts
    }

    /// Internet outages in the selected country over the last week, seen by
    /// at least two independent signals.
    var internetOutages: [InternetOutage] = []
    /// WHO outbreak reports about the selected country, newest per disease.
    var outbreakReports: [OutbreakReport] = []
    /// Reports per country, built once from WHO's list.
    @ObservationIgnored private var outbreakIndex: [String: [OutbreakReport]]?

    private func updateInternetOutages() async {
        guard let country = current, let code = country.cca2 else { return }
        let outages = (try? await services.internetOutageService.getOutages(countryCode: code)) ?? []
        guard !Task.isCancelled, current?.id == country.id else { return }
        internetOutages = outages
    }

    private func updateOutbreakReports() async {
        guard let country = current, let code = country.cca2 else { return }
        if outbreakIndex == nil, let reports = try? await services.outbreakService.getReports() {
            let countries = countries
            outbreakIndex = await Task.detached(priority: .userInitiated) {
                OutbreakCountryMatcher.index(reports, countries: countries)
            }.value
        }
        guard !Task.isCancelled, current?.id == country.id else { return }
        outbreakReports = outbreakIndex?[code] ?? []
    }

    private func updateExchangeRates() async {
        guard let country = current else { return }
        let selection = travelSelection
        let home = homeCurrency
        let destinationCurrencies = (country.currencies ?? [:]).keys.sorted().filter { $0 != home }
        guard !destinationCurrencies.isEmpty,
              let rates = try? await services.exchangeRateService.getRates(base: home),
              !Task.isCancelled, travelSelection == selection else { return }
        exchangeRates = destinationCurrencies.compactMap { code in
            rates.rates[code].map { ExchangeRate(home: home, destination: code, rate: $0, date: rates.date) }
        }
    }

    struct TravelSelection: Equatable {
        let destinationID: Country.ID?
        let nationalityID: Country.ID?
    }

    var travelSelection: TravelSelection {
        TravelSelection(destinationID: current?.id, nationalityID: nationality?.id)
    }

    func refreshDestination() async {
        guard !Task.isCancelled else { return }
        advisoryStatus = nil
        destinationGuide = nil
        isLoadingDestinationGuide = current?.cca2 != nil
        destinationWeather = nil
        recentEvents = nil
        disasterAlerts = []
        internetOutages = []
        outbreakReports = []

        async let map: Void = updateRegion()
        async let advisory: Void = updateAdvisoryStatus()
        async let weather: Void = updateWeather()
        async let events: Void = updateRecentEvents()
        async let alerts: Void = updateDisasterAlerts()
        async let outages: Void = updateInternetOutages()
        async let outbreaks: Void = updateOutbreakReports()
        _ = await (map, advisory, weather, events, alerts, outages, outbreaks)
    }

    func refreshPassportInformation() async {
        guard !Task.isCancelled else { return }
        admissoryStatus = nil
        exchangeRates = []

        async let visa: Void = updateAdmissoryStatus()
        async let rates: Void = updateExchangeRates()
        _ = await (visa, rates)
    }

    private func updateAdmissoryStatus() async {
        let selection = travelSelection
        guard let passport = nationality?.cca2, let destination = current?.cca2 else { return }
        let status = try? await services.admissoryService.getAdmissoryStatus(passport: passport, destination: destination)
        guard !Task.isCancelled, travelSelection == selection else { return }
        admissoryStatus = status
    }

    private func updateAdvisoryStatus() async {
        guard let country = current, let code = country.cca2 else { return }
        let status = try? await services.advisoryService.getAdvisoryStatus(destination: code)
        guard !Task.isCancelled, current?.id == country.id else { return }
        advisoryStatus = status
        guard let information = status?.data.eng else {
            isLoadingDestinationGuide = false
            return
        }
        // Parsing a country's advice takes tens of milliseconds, so keep it
        // off the main thread.
        let guide = await Task.detached(priority: .userInitiated) {
            DestinationGuide(information: information)
        }.value
        // Another country may have been chosen while parsing.
        guard !Task.isCancelled, current?.id == country.id else { return }
        destinationGuide = guide
        isLoadingDestinationGuide = false
    }

    // MARK: Map layers

    /// Live aircraft. Off also stops polling OpenSky.
    var showsFlights: Bool {
        didSet {
            guard showsFlights != oldValue else { return }
            preferences[.flights] = showsFlights
            if showsFlights {
                startUpdatingFlightData()
            } else {
                stopUpdatingFlightData()
                selectedFlight = nil
                flightAnnotations = []
                liveFlights = [:]
                lastOpenSkyFlights = []
                totalFlightCount = 0
                flightsPausedUntil = nil
            }
        }
    }

    var showsPowerGrid: Bool {
        didSet { preferences[.powerGrid] = showsPowerGrid }
    }

    var showsEarthAtNight: Bool {
        didSet { preferences[.earthAtNight] = showsEarthAtNight }
    }

    var showsVIIRSImagery: Bool {
        didSet { preferences[.viirsImagery] = showsVIIRSImagery }
    }

    func loadVIIRSImageryDates(for product: VIIRSImageryService.Product) async throws -> [String] {
        try await services.viirsImageryService.getAvailableDates(for: product)
    }

    /// Undersea cables and their landing points.
    var showsCables: Bool {
        didSet {
            guard showsCables != oldValue else { return }
            preferences[.cables] = showsCables
            if !showsCables { selectedCableID = nil }
            Task { await loadCablesIfNeeded() }
        }
    }

    @ObservationIgnored private var allCables: [SubmarineCable] = []
    @ObservationIgnored private var allLandingPoints: [CableLandingPoint] = []
    /// The cables and landing points to draw: empty while the layer is off.
    var cables: [SubmarineCable] = []
    var landingPoints: [CableLandingPoint] = []
    var cableLoadingError: String?

    func loadCablesIfNeeded() async {
        guard showsCables else {
            cables = []
            landingPoints = []
            return
        }
        if allCables.isEmpty {
            do {
                let data = try await services.cableService.getCables()
                allCables = data.cables
                allLandingPoints = data.landingPoints
                cableLoadingError = nil
            } catch {
                cableLoadingError = "Couldn't load undersea cables."
                return
            }
        }
        guard showsCables else { return }
        cables = allCables
        landingPoints = allLandingPoints
    }

    /// The cable tapped on the map; its details sheet is open while set.
    var selectedCableID: String? {
        didSet {
            guard selectedCableID != oldValue else { return }
            selectedCableDetails = nil
            if let id = selectedCableID {
                Task { await loadCableDetails(id: id) }
            }
        }
    }
    var selectedCableDetails: CableDetails?

    var selectedCable: SubmarineCable? {
        selectedCableID.flatMap { id in cables.first { $0.id == id } }
    }

    private func loadCableDetails(id: String) async {
        let details = try? await services.cableService.getDetails(cableID: id)
        guard selectedCableID == id else { return }
        selectedCableDetails = details
    }

    /// Earthquakes, cyclones, floods, wildfires and erupting volcanoes.
    var showsHazards: Bool {
        didSet {
            guard showsHazards != oldValue else { return }
            preferences[.hazards] = showsHazards
            if !showsHazards { selectedHazard = nil }
            Task { await updateHazards() }
        }
    }

    /// The hazards to draw: empty while the layer is off.
    var hazards: [NaturalHazard] = []
    var cycloneTracks: [CycloneTrack] = []
    /// The hazard tapped on the map; its details sheet is open while set.
    /// Kept as is, so a refresh doesn't change the sheet under the user.
    var selectedHazard: NaturalHazard?

    func selectHazard(id: String) {
        selectedHazard = hazards.first { $0.id == id }
    }

    /// Loads hazards, or clears them while the layer is off. The service
    /// keeps them for 15 minutes, so this is cheap to call again.
    func updateHazards() async {
        guard showsHazards else {
            hazards = []
            cycloneTracks = []
            return
        }
        guard let loaded = try? await services.hazardService.getHazards(), showsHazards else { return }
        if loaded != hazards {
            hazards = loaded
        }
        var tracks: [CycloneTrack] = []
        for cyclone in loaded where cyclone.kind == .cyclone {
            if let track = try? await services.hazardService.getTrack(for: cyclone) {
                tracks.append(track)
            }
        }
        guard showsHazards, tracks != cycloneTracks else { return }
        cycloneTracks = tracks
    }

    // MARK: Live flights

    @ObservationIgnored private var flightUpdateTask: Task<Void, Never>?
    /// The latest flights from both feeds, by ICAO address.
    private var liveFlights: [String: LiveFlight] = [:]
    /// OpenSky's last answer, kept while it rate limits us so military
    /// updates don't wipe the civil traffic.
    @ObservationIgnored private var lastOpenSkyFlights: [LiveFlight] = []

    var flightAnnotations: [FlightAnnotation] = []
    var selectedFlight: FlightAnnotation?
    /// Set while OpenSky is rate limiting us; live flights resume at this time.
    var flightsPausedUntil: Date?
    /// Flights OpenSky returned for the visible area, before capping to
    /// `maxVisibleFlights`.
    var totalFlightCount = 0

    /// Most aircraft drawn at once. MapKit starts to stutter beyond a few
    /// hundred moving markers.
    static let maxVisibleFlights = 500

    var isShowingSubsetOfFlights: Bool {
        flightAnnotations.count < totalFlightCount
    }

    var selectedLiveFlight: LiveFlight? {
        selectedFlight.flatMap { flight(for: $0.id) }
    }

    /// Latest live values for a flight, if it's in the current data.
    func flight(for icao24: String) -> LiveFlight? {
        liveFlights[icao24.lowercased()]
    }

    /// Registration details for the selected flight, once loaded.
    var selectedAircraft: AircraftInfo?
    /// Scheduled route for the selected flight, if adsbdb knows it and the
    /// aircraft's position fits it.
    var selectedRoute: FlightRoute?
    var isLoadingFlightDetails = false

    func loadFlightDetails() async {
        // On deselect, keep the details so the sheet doesn't empty while it
        // slides away; they're replaced when the next flight is selected.
        guard !Task.isCancelled, let flightID = selectedFlight?.id else { return }
        selectedAircraft = nil
        selectedRoute = nil
        let callsign = selectedLiveFlight?.callsign ?? ""

        isLoadingFlightDetails = true
        async let aircraft = try? services.flightDetailsService.getAircraft(icao24: flightID)
        async let route = callsign.isEmpty ? nil : try? services.flightDetailsService.getRoute(callsign: callsign)
        let (loadedAircraft, loadedRoute) = await (aircraft, route)

        // Another flight may have been selected while we waited.
        guard !Task.isCancelled, selectedFlight?.id == flightID else { return }
        isLoadingFlightDetails = false
        selectedAircraft = loadedAircraft
        if let loadedRoute, let coordinate = selectedLiveFlight?.coordinate,
           loadedRoute.isPlausible(forAircraftAt: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) {
            selectedRoute = loadedRoute
        }
    }

    func startUpdatingFlightData() {
        guard showsFlights, flightUpdateTask == nil else { return }
        flightUpdateTask = Task { [weak self] in
            while !Task.isCancelled {
                guard await self?.updateFlightData() != nil else { return }
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    func stopUpdatingFlightData() {
        flightUpdateTask?.cancel()
        flightUpdateTask = nil
    }

    func updateViewport(_ rect: MKMapRect) {
        stopUpdatingFlightData()
        visibleRect = rect
        startUpdatingFlightData()
    }

    private func openSkyFlights(in region: (latitude: CoordinateSpan, longitude: CoordinateSpan)) async -> Result<[LiveFlight], Error> {
        do {
            return .success(try await services.flightService.getFlights(latitudeSpan: region.latitude, longitudeSpan: region.longitude))
        } catch {
            return .failure(error)
        }
    }

    /// Polls OpenSky for the visible area and adsb.lol for military
    /// aircraft at the same time, and draws both as one set of flights.
    private func updateFlightData() async {
        let viewport = visibleRect
        let visibleRegion = MapRegionCalculator.bounds(of: viewport)
        async let openSky = openSkyFlights(in: visibleRegion)
        async let military = try? services.flightService.getMilitaryFlights()
        let (openSkyResult, militaryFlights) = await (openSky, military)

        // The viewport or layer may have changed while this poll was running.
        guard !Task.isCancelled, showsFlights else { return }
        switch openSkyResult {
        case .success(let flights):
            lastOpenSkyFlights = flights
            flightsPausedUntil = nil
        case .failure(HTTPError.rateLimited(let retryAfter)):
            flightsPausedUntil = retryAfter.map { Date().addingTimeInterval($0) }
        case .failure(let error):
            print(error)
        }

        // The military list covers the whole world; keep the ones in view.
        let militaryInView = (militaryFlights ?? []).filter {
            visibleRegion.latitude.contains($0.coordinate.latitude)
                && visibleRegion.longitude.contains($0.coordinate.longitude)
        }
        let flights = lastOpenSkyFlights.merging(military: militaryInView)
        liveFlights = Dictionary(flights.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let annotations = flights.map(FlightAnnotation.init(flight:))
        totalFlightCount = annotations.count
        flightAnnotations = annotations.nearest(
            to: viewport,
            limit: Self.maxVisibleFlights,
            keeping: selectedFlight?.id
        )
    }
}
