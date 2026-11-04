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

        init() {
            self.advisoryService = AdvisoryService(networkService: networkService)
            self.admissoryService = AdmissoryService(networkService: networkService)
            self.countriesService = CountriesService(networkService: networkService)
            self.openSkyService = OpenSkyService(networkService: networkService)
            self.flightDetailsService = FlightDetailsService(networkService: networkService)
            self.weatherService = WeatherService(networkService: networkService)
            self.exchangeRateService = ExchangeRateService(networkService: networkService)
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
            exchangeRateService: serviceContainer.exchangeRateService
        )
        WindowGroup {
            MainMapView(viewModel: mainMapViewModel)
        }
    }
}
