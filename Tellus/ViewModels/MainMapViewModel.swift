//
//  MainMapViewModel.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2024-07-23.
//

import Foundation
import MapKit
import Combine

final class FlightAnnotation: NSObject, MKAnnotation, Identifiable {
    let id: String
    var coordinate: CLLocationCoordinate2D
    var track: Float?
    
    init(id: String, coordinate: CLLocationCoordinate2D, track: Float?) {
        self.id = id
        self.coordinate = coordinate
        self.track = track
    }
}

@Observable
final class MainMapViewModel {
    
    private let countriesService: CountriesServiceProtocol
    private let admissoryService: AdmissoryServiceProtocol
    private let advisoryService: AdvisoryServiceProtocol
    private let openSkyService: OpenSkyServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    
    init(countriesService: CountriesServiceProtocol, admissoryService: AdmissoryServiceProtocol, advisoryService: AdvisoryServiceProtocol,
         openSkyService: OpenSkyServiceProtocol) {
        self.countriesService = countriesService
        self.admissoryService = admissoryService
        self.advisoryService = advisoryService
        self.openSkyService = openSkyService
    }

    var region: MKCoordinateRegion = .init(.world)
    var visibleRect: MKMapRect = .world
    var countries: [Country] = []
    var current: Country?
    var nationality: Country? = getPersistedNationality()
    var admissoryStatus: AdmissoryStatus?
    var advisoryStatus: AdvisoryStatus?
    var flightData: FlightData?
    var flightAnnotations: [FlightAnnotation] = []
    var selectedFlight: FlightAnnotation?
    
    var selectedState: StateVector? {
        return flightData?.states.first { $0.icao24 == selectedFlight?.id }
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
        advisoryStatus = await retrieveAdvisoryStatus()
    }
    
    func updateFlightData() {
        Timer.publish(every: 15, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                Task {
                    do {
                        let data = try await self.retrieveFlightData()
                        self.flightData = data
                        let flightAnnotations: [FlightAnnotation]? = data?.states.compactMap { state -> FlightAnnotation? in
                            guard let latitude = state.latitude, let longitude = state.longitude else {
                                return nil
                            }
                            return .init(id: state.icao24, coordinate: .init(latitude: CLLocationDegrees(latitude), longitude: CLLocationDegrees(longitude)), track: state.trueTrack)
                        }
                        self.flightAnnotations = flightAnnotations ?? []
                    } catch {
                        print(error)
                    }
                }
            }.store(in: &cancellables)
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
    
    func calculateRegion(area: Double, latitude: CLLocationDegrees, longitude: CLLocationDegrees) -> MKCoordinateRegion {
        
        // Calculate deltas
        let latitudeDelta = sqrt(area) / 110
        let longitudeDelta = (sqrt(area) / 110) + latitudeDelta
        
        // Calculate the span
        let span = MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        
        // Create the coordinate region
        let centerCoordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return MKCoordinateRegion(center: centerCoordinate, span: span)
    }
    
    func calculateVisibleRegion(visibleMapRect: MKMapRect) -> (latitude: CoordinateSpan, longitude: CoordinateSpan) {
        let region = MKCoordinateRegion(visibleMapRect)
        let minLatitude = region.center.latitude - region.span.latitudeDelta / 2
        let maxLatitude = region.center.latitude + region.span.latitudeDelta / 2
        let minLongitude = region.center.longitude - region.span.longitudeDelta / 2
        let maxLongitude = region.center.longitude + region.span.longitudeDelta / 2

        let latitudeSpan = CoordinateSpan(minimum: minLatitude, maximum: maxLatitude)
        let longitudeSpan = CoordinateSpan(minimum: minLongitude, maximum: maxLongitude)
        return (latitude: latitudeSpan, longitude: longitudeSpan)
    }
    
    func findRegion(by name: String) async -> MKCoordinateRegion? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = name
        let results = try? await MKLocalSearch(request: request).start()
        return results?.boundingRegion
    }
    
    func retrieveCountries() async {

        self.countries = try! await countriesService.getAllCountries()
        self.selectRandomCountry()
    }
    
    func retrieveAdmissoryStatus() async -> AdmissoryStatus? {
        guard let current else {
            return nil
        }
        
        guard let passport = nationality?.cca2,
              let destination = current.cca2 else {
            return nil
        }
        
        return try? await admissoryService.getAdmissoryStatus(passport: passport, destination: destination)
    }
    
    func retrieveAdvisoryStatus() async -> AdvisoryStatus? {
        guard let current else {
            return nil
        }
        
        guard let destination = current.cca2 else {
            return nil
        }
        
        let status = try? await advisoryService.getAdvisoryStatus(destination: destination)
        return status
    }
    
    func retrieveFlightData() async throws -> FlightData? {
        let visibleRegion = calculateVisibleRegion(visibleMapRect: visibleRect)
        return try await openSkyService.getAllFlights(latitudeSpan: visibleRegion.latitude, longitudeSpan: visibleRegion.longitude)
    }
}
