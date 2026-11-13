struct CountryGuideServices {
    let advisoryService: AdvisoryServiceProtocol
    let admissoryService: AdmissoryServiceProtocol
    let weatherService: WeatherServiceProtocol
    let exchangeRateService: ExchangeRateServiceProtocol
    let recentEventsService: RecentEventsServiceProtocol
    let emberElectricityService: EmberElectricityServiceProtocol
    let countryProfileService: CountryProfileServiceProtocol
    let democracyDataset = DemocracyDatasetStore()
    let eurostatPriceService: EurostatPriceService
    let disasterAlertService: DisasterAlertServiceProtocol
    let internetOutageService: InternetOutageServiceProtocol
    let outbreakService: OutbreakServiceProtocol
}

extension CountryGuideServices {
    init(networkService: NetworkServiceProtocol) {
        self.init(
            advisoryService: AdvisoryService(networkService: networkService),
            admissoryService: AdmissoryService(networkService: networkService),
            weatherService: WeatherService(networkService: networkService),
            exchangeRateService: ExchangeRateService(networkService: networkService),
            recentEventsService: RecentEventsService(networkService: networkService),
            emberElectricityService: EmberElectricityService(networkService: networkService),
            countryProfileService: CountryProfileService(networkService: networkService),
            eurostatPriceService: EurostatPriceService(networkService: networkService),
            disasterAlertService: DisasterAlertService(networkService: networkService),
            internetOutageService: InternetOutageService(networkService: networkService),
            outbreakService: OutbreakService(networkService: networkService)
        )
    }
}
