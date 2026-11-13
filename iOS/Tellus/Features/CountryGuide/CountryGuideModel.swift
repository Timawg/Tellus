import Foundation

@MainActor
@Observable
final class CountryGuideModel {
    private let services: CountryGuideServices

    struct TravelSelection: Equatable {
        let destinationID: Country.ID?
        let nationalityID: Country.ID?
    }

    private(set) var travelSelection = TravelSelection(destinationID: nil, nationalityID: nil)

    private(set) var advisoryStatus: AdvisoryStatus?
    private(set) var advisoryLoadFailed = false
    /// The Canadian travel advisory, destination advice and emergency numbers.
    private(set) var destinationGuide: DestinationGuide?
    private(set) var isLoadingDestinationGuide = false
    private(set) var admissoryStatus: AdmissoryStatus?

    /// Weather at the selected country's capital.
    private(set) var destinationWeather: DestinationWeather?

    /// What one unit of the home currency buys in each of the selected
    /// country's currencies. Empty when they share a currency.
    private(set) var exchangeRates: [ExchangeRate] = []

    /// Dated events from Wikipedia's "<year> in <country>" article.
    private(set) var recentEvents: RecentEvents?
    /// Current GDACS orange and red alerts for the selected country.
    private(set) var disasterAlerts: [DisasterAlert] = []

    /// Internet outages in the selected country over the last week, seen by
    /// at least two independent signals.
    private(set) var internetOutages: [InternetOutage] = []
    /// WHO outbreak reports about the selected country, newest per disease.
    private(set) var outbreakReports: [OutbreakReport] = []
    /// Reports per country, built once from WHO's list.
    @ObservationIgnored private var outbreakIndex: [String: [OutbreakReport]]?

    init(services: CountryGuideServices) {
        self.services = services
    }

    func updateSelection(destination: Country?, passport: Country?) {
        let selection = TravelSelection(destinationID: destination?.id, nationalityID: passport?.id)
        guard selection != travelSelection else { return }
        if selection.destinationID != travelSelection.destinationID {
            clearDestination(isLoading: destination?.cca2 != nil)
        }
        clearPassportInformation()
        travelSelection = selection
    }

    func refreshDestination(_ country: Country?, countries: [Country]) async {
        guard !Task.isCancelled, travelSelection.destinationID == country?.id else { return }
        clearDestination(isLoading: country?.cca2 != nil)
        guard let country else { return }

        async let advisory: Void = updateAdvisoryStatus(for: country)
        async let weather: Void = updateWeather(for: country)
        async let events: Void = updateRecentEvents(for: country)
        async let alerts: Void = updateDisasterAlerts(for: country)
        async let outages: Void = updateInternetOutages(for: country)
        async let outbreaks: Void = updateOutbreakReports(for: country, countries: countries)
        _ = await (advisory, weather, events, alerts, outages, outbreaks)
    }

    func refreshPassportInformation(destination: Country?, passport: Country?) async {
        let selection = TravelSelection(destinationID: destination?.id, nationalityID: passport?.id)
        guard !Task.isCancelled, travelSelection == selection else { return }
        clearPassportInformation()
        guard let destination else { return }

        async let visa: Void = updateAdmissoryStatus(destination: destination, passport: passport, selection: selection)
        async let rates: Void = updateExchangeRates(for: destination, passport: passport, selection: selection)
        _ = await (visa, rates)
    }

    func loadElectricityProfile(countryCode: String) async throws -> CountryElectricityProfile? {
        try await services.emberElectricityService.getProfile(countryCode: countryCode)
    }

    func loadCountryProfile(countryCode: String) async throws -> [CountryIndicatorObservation] {
        try await services.countryProfileService.getProfile(countryCode: countryCode)
    }

    func loadDemocracyProfile(countryCode: String?) async throws -> DemocracyProfile {
        try await services.democracyDataset.profile(countryCode: countryCode)
    }

    func loadHomicideTrend(countryCode: String) async throws -> [AnnualObservation] {
        try await services.countryProfileService.getHomicideTrend(countryCode: countryCode)
    }

    func loadPriceLevels() async throws -> EurostatPriceLevels {
        try await services.eurostatPriceService.getPriceLevels()
    }

    func travelStatuses(passport: Country?) -> [TravelStatus] {
        [
            TravelStatus.advisory(advisoryStatus),
            TravelStatus.visa(admissoryStatus, passport: passport),
            TravelStatus.health(outbreakReports),
            TravelStatus.disasters(disasterAlerts),
        ].compactMap { $0 }
    }

    private func clearDestination(isLoading: Bool) {
        advisoryStatus = nil
        advisoryLoadFailed = false
        destinationGuide = nil
        isLoadingDestinationGuide = isLoading
        destinationWeather = nil
        recentEvents = nil
        disasterAlerts = []
        internetOutages = []
        outbreakReports = []
    }

    private func clearPassportInformation() {
        admissoryStatus = nil
        exchangeRates = []
    }

    private func updateAdmissoryStatus(destination: Country, passport: Country?, selection: TravelSelection) async {
        guard let passport = passport?.cca2, let destination = destination.cca2 else { return }
        let status = try? await services.admissoryService.getAdmissoryStatus(passport: passport, destination: destination)
        guard !Task.isCancelled, travelSelection == selection else { return }
        admissoryStatus = status
    }

    private func updateAdvisoryStatus(for country: Country) async {
        guard let code = country.cca2 else { return }
        let status: AdvisoryStatus
        do {
            status = try await services.advisoryService.getAdvisoryStatus(destination: code)
        } catch {
            guard !Task.isCancelled, travelSelection.destinationID == country.id else { return }
            if case HTTPError.invalidStatus(code: 404, _) = error {
                advisoryLoadFailed = false
            } else {
                advisoryLoadFailed = true
            }
            isLoadingDestinationGuide = false
            return
        }
        guard !Task.isCancelled, travelSelection.destinationID == country.id else { return }
        advisoryStatus = status
        let information = status.data.eng
        // Parsing a country's advice takes tens of milliseconds, so keep it
        // off the main thread.
        let guide = await Task.detached(priority: .userInitiated) {
            DestinationGuide(information: information)
        }.value
        // Another country may have been chosen while parsing.
        guard !Task.isCancelled, travelSelection.destinationID == country.id else { return }
        destinationGuide = guide
        isLoadingDestinationGuide = false
    }

    private func updateWeather(for country: Country) async {
        let weather = try? await services.weatherService.getWeather(for: country)
        // Another country may have been chosen while loading.
        guard !Task.isCancelled, travelSelection.destinationID == country.id else { return }
        destinationWeather = weather
    }

    private func updateRecentEvents(for country: Country) async {
        let events = try? await services.recentEventsService.getRecentEvents(for: country)
        guard !Task.isCancelled, travelSelection.destinationID == country.id else { return }
        recentEvents = events
    }

    private func updateDisasterAlerts(for country: Country) async {
        guard let code = country.cca2 else { return }
        let alerts = (try? await services.disasterAlertService.getAlerts(countryCode: code)) ?? []
        guard !Task.isCancelled, travelSelection.destinationID == country.id else { return }
        disasterAlerts = alerts
    }

    private func updateInternetOutages(for country: Country) async {
        guard let code = country.cca2 else { return }
        let outages = (try? await services.internetOutageService.getOutages(countryCode: code)) ?? []
        guard !Task.isCancelled, travelSelection.destinationID == country.id else { return }
        internetOutages = outages
    }

    private func updateOutbreakReports(for country: Country, countries: [Country]) async {
        guard let code = country.cca2 else { return }
        if outbreakIndex == nil, let reports = try? await services.outbreakService.getReports() {
            outbreakIndex = await Task.detached(priority: .userInitiated) {
                OutbreakCountryMatcher.index(reports, countries: countries)
            }.value
        }
        guard !Task.isCancelled, travelSelection.destinationID == country.id else { return }
        outbreakReports = outbreakIndex?[code] ?? []
    }

    /// The currency rates are shown from: the passport country's, else the
    /// device's region's, else US dollars.
    private func homeCurrency(for passport: Country?) -> String {
        passport?.currencies?.keys.sorted().first
            ?? Locale.current.currency?.identifier
            ?? "USD"
    }

    private func updateExchangeRates(for country: Country, passport: Country?, selection: TravelSelection) async {
        let home = homeCurrency(for: passport)
        let destinationCurrencies = (country.currencies ?? [:]).keys.sorted().filter { $0 != home }
        guard !destinationCurrencies.isEmpty,
              let rates = try? await services.exchangeRateService.getRates(base: home),
              !Task.isCancelled, travelSelection == selection else { return }
        exchangeRates = destinationCurrencies.compactMap { code in
            rates.rates[code].map { ExchangeRate(home: home, destination: code, rate: $0, date: rates.date) }
        }
    }
}
