//
//  TellusApp.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2023-09-14.
//

import SwiftUI

@main
struct TellusApp: App {
    
    struct ServiceContainer {
        
        private let networkService: NetworkServiceProtocol = NetworkService()
        let advisoryService: AdvisoryServiceProtocol
        let admissoryService: AdmissoryServiceProtocol
        let countriesService: CountriesServiceProtocol
        let openSkyService: OpenSkyServiceProtocol
        let flightDetailsService: FlightDetailsServiceProtocol
        let weatherService: WeatherServiceProtocol
        let exchangeRateService: ExchangeRateServiceProtocol
        let recentEventsService: RecentEventsServiceProtocol
        let disasterAlertService: DisasterAlertServiceProtocol
        let internetOutageService: InternetOutageServiceProtocol
        let outbreakService: OutbreakServiceProtocol
        let cableService: CableServiceProtocol
        let hazardService: HazardServiceProtocol

        init() {
            self.advisoryService = AdvisoryService(networkService: networkService)
            self.admissoryService = AdmissoryService(networkService: networkService)
            self.countriesService = CountriesService(networkService: networkService)
            self.openSkyService = OpenSkyService(networkService: networkService)
            self.flightDetailsService = FlightDetailsService(networkService: networkService)
            self.weatherService = WeatherService(networkService: networkService)
            self.exchangeRateService = ExchangeRateService(networkService: networkService)
            self.recentEventsService = RecentEventsService(networkService: networkService)
            self.disasterAlertService = DisasterAlertService(networkService: networkService)
            self.internetOutageService = InternetOutageService(networkService: networkService)
            self.outbreakService = OutbreakService(networkService: networkService)
            self.cableService = CableService(networkService: networkService)
            self.hazardService = HazardService(networkService: networkService)
        }
    }

    private let serviceContainer = ServiceContainer()
    
    var body: some Scene {
        let mainMapViewModel: MainMapViewModel = .init(
            countriesService: serviceContainer.countriesService,
            admissoryService: serviceContainer.admissoryService,
            advisoryService: serviceContainer.advisoryService, 
            openSkyService: serviceContainer.openSkyService,
            flightDetailsService: serviceContainer.flightDetailsService,
            weatherService: serviceContainer.weatherService,
            exchangeRateService: serviceContainer.exchangeRateService,
            recentEventsService: serviceContainer.recentEventsService,
            disasterAlertService: serviceContainer.disasterAlertService,
            internetOutageService: serviceContainer.internetOutageService,
            outbreakService: serviceContainer.outbreakService,
            cableService: serviceContainer.cableService,
            hazardService: serviceContainer.hazardService
        )
        WindowGroup {
            MainMapView(viewModel: mainMapViewModel)
        }
    }
}
