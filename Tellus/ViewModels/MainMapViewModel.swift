//
//  MainMapViewModel.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2024-07-23.
//

import Foundation
import MapKit
import Combine

@Observable
final class MainMapViewModel {
    
    private let countriesService: CountriesServiceProtocol
    private let admissoryService: AdmissoryServiceProtocol
    private let advisoryService: AdvisoryServiceProtocol
    private let flightService: FlightServiceProtocol
    private let flightDetailsService: FlightDetailsServiceProtocol
    private let weatherService: WeatherServiceProtocol
    private let exchangeRateService: ExchangeRateServiceProtocol
    private let recentEventsService: RecentEventsServiceProtocol
    private let disasterAlertService: DisasterAlertServiceProtocol
    private let internetOutageService: InternetOutageServiceProtocol
    private let outbreakService: OutbreakServiceProtocol
    private let cableService: CableServiceProtocol
    private let hazardService: HazardServiceProtocol
    private var timerSubscription: AnyCancellable?
    /// The latest flights from both feeds, by ICAO address.
    private var liveFlights: [String: LiveFlight] = [:]
    /// OpenSky's last answer, kept while it rate limits us so military
    /// updates don't wipe the civil traffic.
    private var lastOpenSkyFlights: [LiveFlight] = []

    init(
        countriesService: CountriesServiceProtocol,
        admissoryService: AdmissoryServiceProtocol,
        advisoryService: AdvisoryServiceProtocol,
        flightService: FlightServiceProtocol,
        flightDetailsService: FlightDetailsServiceProtocol,
        weatherService: WeatherServiceProtocol,
        exchangeRateService: ExchangeRateServiceProtocol,
        recentEventsService: RecentEventsServiceProtocol,
        disasterAlertService: DisasterAlertServiceProtocol,
        internetOutageService: InternetOutageServiceProtocol,
        outbreakService: OutbreakServiceProtocol,
        cableService: CableServiceProtocol,
        hazardService: HazardServiceProtocol
    ) {
        self.countriesService = countriesService
        self.admissoryService = admissoryService
        self.advisoryService = advisoryService
        self.flightService = flightService
        self.flightDetailsService = flightDetailsService
        self.weatherService = weatherService
        self.exchangeRateService = exchangeRateService
        self.recentEventsService = recentEventsService
        self.disasterAlertService = disasterAlertService
        self.internetOutageService = internetOutageService
        self.outbreakService = outbreakService
        self.cableService = cableService
        self.hazardService = hazardService
    }

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

    @MainActor
    func updateWeather() async {
        guard let country = current else { return }
        destinationWeather = nil
        let weather = try? await weatherService.getWeather(for: country)
        // Another country may have been chosen while loading.
        guard current?.cca2 == country.cca2 else { return }
        destinationWeather = weather
    }

    /// Dated events from Wikipedia's "<year> in <country>" article.
    var recentEvents: RecentEvents?
    /// Current GDACS orange and red alerts for the selected country.
    var disasterAlerts: [DisasterAlert] = []

    @MainActor
    func updateRecentEvents() async {
        guard let country = current else { return }
        recentEvents = nil
        let events = try? await recentEventsService.getRecentEvents(for: country)
        guard current?.cca2 == country.cca2 else { return }
        recentEvents = events
    }

    @MainActor
    func updateDisasterAlerts() async {
        guard let country = current, let code = country.cca2 else { return }
        disasterAlerts = []
        let alerts = (try? await disasterAlertService.getAlerts(countryCode: code)) ?? []
        guard current?.cca2 == country.cca2 else { return }
        disasterAlerts = alerts
    }

    /// Internet outages in the selected country over the last week, seen by
    /// at least two independent signals.
    var internetOutages: [InternetOutage] = []
    /// WHO outbreak reports about the selected country, newest per disease.
    var outbreakReports: [OutbreakReport] = []
    /// Reports per country, built once from WHO's list.
    @ObservationIgnored private var outbreakIndex: [String: [OutbreakReport]]?

    @MainActor
    func updateInternetOutages() async {
        guard let country = current, let code = country.cca2 else { return }
        internetOutages = []
        let outages = (try? await internetOutageService.getOutages(countryCode: code)) ?? []
        guard current?.cca2 == country.cca2 else { return }
        internetOutages = outages
    }

    @MainActor
    func updateOutbreakReports() async {
        guard let country = current, let code = country.cca2 else { return }
        outbreakReports = []
        if outbreakIndex == nil, let reports = try? await outbreakService.getReports() {
            let countries = countries
            outbreakIndex = await Task.detached(priority: .userInitiated) {
                OutbreakCountryMatcher.index(reports, countries: countries)
            }.value
        }
        guard current?.cca2 == country.cca2 else { return }
        outbreakReports = outbreakIndex?[code] ?? []
    }

    @MainActor
    func updateExchangeRates() async {
        guard let country = current else { return }
        exchangeRates = []
        let home = homeCurrency
        let destinationCurrencies = (country.currencies ?? [:]).keys.sorted().filter { $0 != home }
        guard !destinationCurrencies.isEmpty,
              let rates = try? await exchangeRateService.getRates(base: home) else {
            exchangeRates = []
            return
        }
        guard current?.cca2 == country.cca2, homeCurrency == home else { return }
        exchangeRates = destinationCurrencies.compactMap { code in
            rates.rates[code].map { ExchangeRate(home: home, destination: code, rate: $0, date: rates.date) }
        }
    }

    @ObservationIgnored var visibleRect: MKMapRect = .world
    var region: MKCoordinateRegion = .init(.world)
    var countries: [Country] = []
    var current: Country?
    var nationality: Country? = getPersistedNationality()
    var advisoryStatus: AdvisoryStatus?
    /// The advisory's entry, health, laws and climate advice and emergency
    /// numbers, without the parts that only apply to Canadians.
    var destinationGuide: DestinationGuide?
    var isLoadingDestinationGuide = false
    var admissoryStatus: AdmissoryStatus?
    var loadingError: String?
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

    @MainActor
    func loadFlightDetails() async {
        // On deselect, keep the details so the sheet doesn't empty while it
        // slides away; they're replaced when the next flight is selected.
        guard let flightID = selectedFlight?.id else { return }
        selectedAircraft = nil
        selectedRoute = nil
        let callsign = selectedLiveFlight?.callsign ?? ""

        isLoadingFlightDetails = true
        async let aircraft = try? flightDetailsService.getAircraft(icao24: flightID)
        async let route = callsign.isEmpty ? nil : try? flightDetailsService.getRoute(callsign: callsign)
        let (loadedAircraft, loadedRoute) = await (aircraft, route)

        // Another flight may have been selected while we waited.
        guard selectedFlight?.id == flightID else { return }
        isLoadingFlightDetails = false
        selectedAircraft = loadedAircraft
        if let loadedRoute, let coordinate = selectedLiveFlight?.coordinate,
           loadedRoute.isPlausible(forAircraftAt: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) {
            selectedRoute = loadedRoute
        }
    }
    
    func selectRandomCountry() {
        guard let randomCountry = countries.randomElement() else {
            return
        }
        current = randomCountry
    }
    
    func persist(nationality: Country?) {
        if let nationality, let encoded = try? JSONEncoder().encode(nationality) {
            UserDefaults.standard.set(encoded, forKey: "nationality")
        }
    }
    
    static func getPersistedNationality() -> Country? {
        guard let data = UserDefaults.standard.object(forKey: "nationality") as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(Country.self, from: data)
    }
    
    func updateAdmissoryStatus() async {
        admissoryStatus = await retrieveAdmissoryStatus()
    }
    
    @MainActor
    func updateAdvisoryStatus() async {
        let country = current?.cca2
        destinationGuide = nil
        isLoadingDestinationGuide = true
        let status = await retrieveAdvisoryStatus()
        guard current?.cca2 == country else { return }
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
        guard current?.cca2 == country else { return }
        destinationGuide = guide
        isLoadingDestinationGuide = false
    }

    /// Countries sharing a border with `country`, by name.
    func neighbours(of country: Country) -> [Country] {
        let codes = Set(country.borders ?? [])
        return countries.filter { $0.cca3.map(codes.contains) ?? false }
    }
    
    var timerPublisher: Timer.TimerPublisher {
        return Timer.publish(every: 15, on: .main, in: .common)
    }
    
    @MainActor
    func startUpdatingFlightData() {
        guard showsFlights else { return }
        Task {
            await updateFlightData()
            timerSubscription = timerPublisher
                .autoconnect()
                .sink(receiveValue: { _ in
                    Task {
                        await self.updateFlightData()
                    }
                })
        }
    }
    
    func stopUpdatingFlightData() {
        timerSubscription?.cancel()
    }

    // MARK: Map layers

    /// Live aircraft. Off also stops polling OpenSky.
    var showsFlights: Bool = UserDefaults.standard.object(forKey: "showsFlights") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(showsFlights, forKey: "showsFlights")
            if showsFlights {
                Task { @MainActor in self.startUpdatingFlightData() }
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

    /// Undersea cables and their landing points.
    var showsCables: Bool = UserDefaults.standard.bool(forKey: "showsCables") {
        didSet {
            UserDefaults.standard.set(showsCables, forKey: "showsCables")
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

    @MainActor
    func loadCablesIfNeeded() async {
        guard showsCables else {
            cables = []
            landingPoints = []
            return
        }
        if allCables.isEmpty {
            do {
                let data = try await cableService.getCables()
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

    @MainActor
    private func loadCableDetails(id: String) async {
        let details = try? await cableService.getDetails(cableID: id)
        guard selectedCableID == id else { return }
        selectedCableDetails = details
    }

    /// Earthquakes, cyclones, floods, wildfires and erupting volcanoes.
    var showsHazards: Bool = UserDefaults.standard.object(forKey: "showsHazards") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(showsHazards, forKey: "showsHazards")
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
    @MainActor
    func updateHazards() async {
        guard showsHazards else {
            hazards = []
            cycloneTracks = []
            return
        }
        guard let loaded = try? await hazardService.getHazards(), showsHazards else { return }
        if loaded != hazards {
            hazards = loaded
        }
        var tracks: [CycloneTrack] = []
        for cyclone in loaded where cyclone.kind == .cyclone {
            if let track = try? await hazardService.getTrack(for: cyclone) {
                tracks.append(track)
            }
        }
        guard showsHazards, tracks != cycloneTracks else { return }
        cycloneTracks = tracks
    }
    
    func updateRegion() {
        guard let current else {
            return
        }
        if let area = current.area {
            let centerLatitude: CLLocationDegrees = current.latlng[0]
            let centerLongitude: CLLocationDegrees = current.latlng[1]
            self.region = calculateRegion(area: area, latitude: centerLatitude, longitude: centerLongitude)
        } else {
            guard let name = current.name?.common else {
                return
            }
            Task {
                guard let region = await findRegion(by: name) else {
                    return
                }
                self.region = region
            }
        }
    }

    func retrieveCountries() async {
        do {
            // Alphabetical, so the pickers are easy to scan.
            self.countries = try await countriesService.getAllCountries().sorted {
                ($0.name?.common ?? "").localizedStandardCompare($1.name?.common ?? "") == .orderedAscending
            }
            self.loadingError = nil
            self.selectRandomCountry()
        } catch {
            self.loadingError = "Could not load countries. Please check your connection and try again."
        }
    }
    
    private func calculateRegion(area: Double, latitude: CLLocationDegrees, longitude: CLLocationDegrees) -> MKCoordinateRegion {
        
        let latitudeDelta = sqrt(area) / 110
        let longitudeDelta = (sqrt(area) / 110) + latitudeDelta
        
        let span = MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        
        let centerCoordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return MKCoordinateRegion(center: centerCoordinate, span: span)
    }
    
    private func calculateVisibleRegion(visibleMapRect: MKMapRect) -> (latitude: CoordinateSpan, longitude: CoordinateSpan) {
        let region = MKCoordinateRegion(visibleMapRect)
        let minLatitude = region.center.latitude - region.span.latitudeDelta / 2
        let maxLatitude = region.center.latitude + region.span.latitudeDelta / 2
        let minLongitude = region.center.longitude - region.span.longitudeDelta / 2
        let maxLongitude = region.center.longitude + region.span.longitudeDelta / 2

        let latitudeSpan = CoordinateSpan(minimum: minLatitude, maximum: maxLatitude)
        let longitudeSpan = CoordinateSpan(minimum: minLongitude, maximum: maxLongitude)
        return (latitude: latitudeSpan, longitude: longitudeSpan)
    }
    
    private func findRegion(by name: String) async -> MKCoordinateRegion? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = name
        let results = try? await MKLocalSearch(request: request).start()
        return results?.boundingRegion
    }
    
    private func retrieveAdmissoryStatus() async -> AdmissoryStatus? {
        guard let current else {
            return nil
        }
        
        guard let passport = nationality?.cca2,
              let destination = current.cca2 else {
            return nil
        }
        
        return try? await admissoryService.getAdmissoryStatus(passport: passport, destination: destination)
    }
    
    private func retrieveAdvisoryStatus() async -> AdvisoryStatus? {
        guard let current else {
            return nil
        }
        
        guard let destination = current.cca2 else {
            return nil
        }
        
        let status = try? await advisoryService.getAdvisoryStatus(destination: destination)
        return status
    }
    
    private func openSkyFlights(in region: (latitude: CoordinateSpan, longitude: CoordinateSpan)) async -> Result<[LiveFlight], Error> {
        do {
            return .success(try await flightService.getFlights(latitudeSpan: region.latitude, longitudeSpan: region.longitude))
        } catch {
            return .failure(error)
        }
    }

    /// Polls OpenSky for the visible area and adsb.lol for military
    /// aircraft at the same time, and draws both as one set of flights.
    @MainActor
    private func updateFlightData() async {
        let visibleRegion = calculateVisibleRegion(visibleMapRect: visibleRect)
        async let openSky = openSkyFlights(in: visibleRegion)
        async let military = try? flightService.getMilitaryFlights()
        let (openSkyResult, militaryFlights) = await (openSky, military)

        // Flights may have been switched off while this poll was running.
        guard showsFlights else { return }
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
            to: visibleRect,
            limit: Self.maxVisibleFlights,
            keeping: selectedFlight?.id
        )
    }
}
