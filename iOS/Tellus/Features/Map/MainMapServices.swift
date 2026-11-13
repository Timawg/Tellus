struct MainMapServices {

    let countriesService: CountriesServiceProtocol
    let viirsImageryService: VIIRSImageryServiceProtocol
    let gpsJamService: GPSJAMServiceProtocol
    let auroraService: AuroraService
}

extension MainMapServices {
    init(networkService: NetworkServiceProtocol) {
        self.init(
            countriesService: CountriesService(networkService: networkService),
            viirsImageryService: VIIRSImageryService(networkService: networkService),
            gpsJamService: GPSJAMService(networkService: networkService),
            auroraService: AuroraService(networkService: networkService)
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
            flights: flights,
            countryGuide: CountryGuideModel(services: CountryGuideServices(networkService: networkService)),
            cableLayer: CableLayerModel(service: CableService(networkService: networkService), preferences: preferences),
            hazardLayer: HazardLayerModel(service: HazardService(networkService: networkService), preferences: preferences)
        )
    }
}
