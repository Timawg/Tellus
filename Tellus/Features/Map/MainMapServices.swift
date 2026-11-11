struct MainMapServices {

    let advisoryService: AdvisoryServiceProtocol
    let admissoryService: AdmissoryServiceProtocol
    let countriesService: CountriesServiceProtocol
    let weatherService: WeatherServiceProtocol
    let viirsImageryService: VIIRSImageryServiceProtocol
    let exchangeRateService: ExchangeRateServiceProtocol
    let recentEventsService: RecentEventsServiceProtocol
    let emberElectricityService: EmberElectricityServiceProtocol
    let countryProfileService: CountryProfileServiceProtocol
    let eurostatPriceService: EurostatPriceService
    let disasterAlertService: DisasterAlertServiceProtocol
    let internetOutageService: InternetOutageServiceProtocol
    let outbreakService: OutbreakServiceProtocol
    let cableService: CableServiceProtocol
    let gpsJamService: GPSJAMServiceProtocol
    let auroraService: AuroraService
    let hazardService: HazardServiceProtocol
}

extension MainMapServices {
    init(networkService: NetworkServiceProtocol) {
        self.init(
            advisoryService: AdvisoryService(networkService: networkService),
            admissoryService: AdmissoryService(networkService: networkService),
            countriesService: CountriesService(networkService: networkService),
            weatherService: WeatherService(networkService: networkService),
            viirsImageryService: VIIRSImageryService(networkService: networkService),
            exchangeRateService: ExchangeRateService(networkService: networkService),
            recentEventsService: RecentEventsService(networkService: networkService),
            emberElectricityService: EmberElectricityService(networkService: networkService),
            countryProfileService: CountryProfileService(networkService: networkService),
            eurostatPriceService: EurostatPriceService(networkService: networkService),
            disasterAlertService: DisasterAlertService(networkService: networkService),
            internetOutageService: InternetOutageService(networkService: networkService),
            outbreakService: OutbreakService(networkService: networkService),
            cableService: CableService(networkService: networkService),
            gpsJamService: GPSJAMService(networkService: networkService),
            auroraService: AuroraService(networkService: networkService),
            hazardService: HazardService(networkService: networkService)
        )
    }

    @MainActor
    static func makeViewModel(networkService: NetworkServiceProtocol, preferences: MapPreferencesStore) -> MainMapViewModel {
        let flights = LiveFlightsModel(
            flightService: FlightService(networkService: networkService),
            detailsService: FlightDetailsService(networkService: networkService),
            preferences: preferences
        )
        return MainMapViewModel(
            services: MainMapServices(networkService: networkService),
            preferences: preferences,
            flights: flights
        )
    }
}
