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
    private let openSkyService: OpenSkyServiceProtocol
    private let flightDetailsService: FlightDetailsServiceProtocol
    private var timerSubscription: AnyCancellable?
    private var flightData: FlightData?

    init(
        countriesService: CountriesServiceProtocol,
        admissoryService: AdmissoryServiceProtocol,
        advisoryService: AdvisoryServiceProtocol,
        openSkyService: OpenSkyServiceProtocol,
        flightDetailsService: FlightDetailsServiceProtocol
    ) {
        self.countriesService = countriesService
        self.admissoryService = admissoryService
        self.advisoryService = advisoryService
        self.openSkyService = openSkyService
        self.flightDetailsService = flightDetailsService
    }

    @ObservationIgnored var visibleRect: MKMapRect = .world
    var region: MKCoordinateRegion = .init(.world)
    var countries: [Country] = []
    var current: Country?
    var nationality: Country? = getPersistedNationality()
    var advisoryStatus: AdvisoryStatus?
    /// The advisory's laws and culture advice, split into topics, without the
    /// parts that only apply to Canadians.
    var localLaws: [LawSection] = []
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

    var selectedState: StateVector? {
        selectedFlight.flatMap { state(for: $0.id) }
    }

    /// Latest live values for a flight, if it's in the current data.
    func state(for icao24: String) -> StateVector? {
        flightData?.states.first { $0.icao24 == icao24 }
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
        let callsign = selectedState?.callsign?.trimmingCharacters(in: .whitespaces) ?? ""

        isLoadingFlightDetails = true
        async let aircraft = try? flightDetailsService.getAircraft(icao24: flightID)
        async let route = callsign.isEmpty ? nil : try? flightDetailsService.getRoute(callsign: callsign)
        let (loadedAircraft, loadedRoute) = await (aircraft, route)

        // Another flight may have been selected while we waited.
        guard selectedFlight?.id == flightID else { return }
        isLoadingFlightDetails = false
        selectedAircraft = loadedAircraft
        if let loadedRoute,
           let latitude = selectedState?.latitude, let longitude = selectedState?.longitude,
           loadedRoute.isPlausible(forAircraftAt: CLLocation(latitude: CLLocationDegrees(latitude), longitude: CLLocationDegrees(longitude))) {
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
    
    func updateAdvisoryStatus() async {
        let status = await retrieveAdvisoryStatus()
        advisoryStatus = status
        localLaws = status.map {
            LawSection.sections(fromHTML: $0.data.eng.lawsCulture).withoutCanadaSpecificAdvice()
        } ?? []
    }
    
    var timerPublisher: Timer.TimerPublisher {
        return Timer.publish(every: 15, on: .main, in: .common)
    }
    
    @MainActor
    func startUpdatingFlightData() {
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
    
    private func retrieveFlightData() async throws -> FlightData {
        let visibleRegion = calculateVisibleRegion(visibleMapRect: visibleRect)
        return try await openSkyService.getAllFlights(latitudeSpan: visibleRegion.latitude, longitudeSpan: visibleRegion.longitude)
    }

    @MainActor
    private func updateFlightData() async {
        do {
            let data = try await self.retrieveFlightData()
            self.flightData = data
            let annotations = self.getFlightAnnotations(from: data)
            self.totalFlightCount = annotations.count
            self.flightAnnotations = annotations.nearest(
                to: visibleRect,
                limit: Self.maxVisibleFlights,
                keeping: selectedFlight?.id
            )
            self.flightsPausedUntil = nil
        } catch HTTPError.rateLimited(let retryAfter) {
            self.flightsPausedUntil = retryAfter.map { Date().addingTimeInterval($0) }
        } catch {
            print(error)
        }
        
    }
    
    private func getFlightAnnotations(from data: FlightData) -> [FlightAnnotation] {
        let flightAnnotations: [FlightAnnotation] = data.states.compactMap { state -> FlightAnnotation? in
            guard let latitude = state.latitude, let longitude = state.longitude else {
                return nil
            }
            return .init(id: state.icao24, coordinate: .init(latitude: CLLocationDegrees(latitude), longitude: CLLocationDegrees(longitude)), track: state.trueTrack)
        }
        return flightAnnotations
    }
}
