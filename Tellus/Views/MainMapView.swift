//
//  ContentView.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2023-09-14.
//

import SwiftUI
import MapKit

struct MainMapView: View {
    
    @Bindable var viewModel: MainMapViewModel
    @AppStorage("showsEarthAtNight") private var showsEarthAtNight =
        UserDefaults.standard.bool(forKey: "showsDayNight") || UserDefaults.standard.bool(forKey: "showsNightLights")
    @AppStorage("showsVIIRSImagery") private var showsVIIRSImagery = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var viirsDates: [String] = []
    @State private var selectedVIIRSDate: String?
    @State private var viirsLoadFailed = false
    @State private var nightLightsDate: String?
    @State private var nightLightsLoadFailed = false
    /// The tab the country guide is open on; nil while it's closed. The
    /// banner opens the tab it's about.
    @State private var guideTopic: DestinationGuide.Topic?
    @State private var showingNationalityPicker = false
    @State private var isPickingCountry = false

    private var viirsImageryDate: String? {
        guard showsVIIRSImagery else { return nil }
        return selectedVIIRSDate ?? viirsDates.first
    }

    var body: some View {
        MapRepresentable(
            region: $viewModel.region,
            selectedAnnotation: $viewModel.selectedFlight,
            annotations: viewModel.flightAnnotations,
            showsEarthAtNight: showsEarthAtNight,
            nightLightsDate: nightLightsDate,
            viirsImageryDate: viirsImageryDate,
            cables: viewModel.cables,
            landingPoints: viewModel.landingPoints,
            selectedCableID: viewModel.selectedCableID,
            selectCable: { viewModel.selectedCableID = $0 },
            tapCountry: { coordinate in
                Task { await viewModel.selectCountry(at: coordinate) }
            },
            outline: viewModel.selectedBorder,
            hazards: viewModel.hazards,
            cycloneTracks: viewModel.cycloneTracks,
            selectHazard: { viewModel.selectHazard(id: $0) }
        ) {
            viewModel.stopUpdatingFlightData()
        } regionDidChange: { rect in
            viewModel.visibleRect = rect
            viewModel.startUpdatingFlightData()
        }
        .edgesIgnoringSafeArea([.top,.bottom])
        .overlay(alignment: .top) {
            statusViews
        }
        .overlay {
            countryListScrim
        }
        .overlay(alignment: .bottom) {
            bottomStack
        }.task(id: showsVIIRSImagery && scenePhase == .active) {
            guard showsVIIRSImagery, scenePhase == .active else { return }
            await updateVIIRSImageryDates()
        }.task(id: showsEarthAtNight && scenePhase == .active) {
            guard showsEarthAtNight, scenePhase == .active else { return }
            await updateNightLightsDate()
        }.task {
            await viewModel.loadCablesIfNeeded()
        }.task {
            // Hazards change slowly; refresh every 15 minutes while open.
            while !Task.isCancelled {
                await viewModel.updateHazards()
                try? await Task.sleep(for: .seconds(15 * 60))
            }
        }.task {
            await viewModel.retrieveCountries()
            viewModel.updateRegion()
            viewModel.startUpdatingFlightData()
        }.onChange(of: viewModel.current) { oldValue, newValue in
            viewModel.updateRegion()
            Task {
                await viewModel.updateAdvisoryStatus()
                await viewModel.updateAdmissoryStatus()
            }
            Task {
                await viewModel.updateWeather()
            }
            Task {
                await viewModel.updateExchangeRates()
            }
            Task {
                await viewModel.updateRecentEvents()
            }
            Task {
                await viewModel.updateDisasterAlerts()
            }
            Task {
                await viewModel.updateInternetOutages()
            }
            Task {
                await viewModel.updateOutbreakReports()
            }
        }.onChange(of: viewModel.selectedFlight?.id) {
            Task {
                await viewModel.loadFlightDetails()
            }
        }.onChange(of: viewModel.nationality) { oldValue, newValue in
            viewModel.persist(nationality: newValue)
            Task {
                await viewModel.updateAdmissoryStatus()
            }
            Task {
                // The home currency follows the passport.
                await viewModel.updateExchangeRates()
            }
        }
        .sheet(isPresented: .init(
            get: { viewModel.selectedCableID != nil },
            set: { if !$0 { viewModel.selectedCableID = nil } }
        )) {
            if let cable = viewModel.selectedCable {
                CableDetailsView(cable: cable, details: viewModel.selectedCableDetails)
            }
        }
        .sheet(item: $viewModel.selectedHazard) { hazard in
            HazardDetailsView(hazard: hazard)
        }
        .sheet(item: $viewModel.selectedFlight) {
            viewModel.selectedFlight = nil
        } content: { flight in
            FlightDetailsView(viewModel: viewModel, flightID: flight.id)
        }
        .alert("Unable to Load Countries", isPresented: .init(
            get: { viewModel.loadingError != nil },
            set: { if !$0 { viewModel.loadingError = nil } }
        )) {
            Button("Retry") {
                Task { await viewModel.retrieveCountries() }
            }
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.loadingError ?? "")
        }
    }

    @ViewBuilder
    var statusViews: some View {
        if let name = viewModel.current?.name?.common, let flag = viewModel.current?.flagURL {
            VStack(spacing: 10) {
                VStack(spacing: 2) {
                    HStack(alignment: .center, spacing: 8) {
                        AsyncFlagView(flag: flag)
                        Text(name)
                            .font(.headline)
                    }
                    // City-states such as Singapore would repeat their name.
                    if let capital = viewModel.current?.capital?.first, capital != name {
                        Text(capital)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .accessibilityLabel("Capital: \(capital)")
                    }
                }
                liveInfoStrip
                alertBanner
                countryGuideButton
            }
            .sheet(item: $guideTopic) { topic in
                if let country = viewModel.current {
                    DestinationGuideView(
                        country: country,
                        guide: viewModel.destinationGuide,
                        isLoading: viewModel.isLoadingDestinationGuide,
                        weather: viewModel.destinationWeather,
                        exchangeRates: viewModel.exchangeRates,
                        alerts: viewModel.disasterAlerts,
                        outages: viewModel.internetOutages,
                        outbreaks: viewModel.outbreakReports,
                        recentEvents: viewModel.recentEvents,
                        loadCountryProfile: viewModel.loadCountryProfile(countryCode:),
                        initialTopic: topic,
                        advisoryStatus: viewModel.advisoryStatus,
                        admissoryStatus: viewModel.admissoryStatus,
                        passport: viewModel.nationality,
                        neighbours: viewModel.neighbours(of: country)
                    ) { neighbour in
                        viewModel.current = neighbour
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .floatingGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .environment(\.colorScheme, .dark)
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }
    
    /// Opens the country guide. Small dots above it show the travel advisory,
    /// visa, disease outbreak and natural disaster statuses, which the
    /// guide explains.
    private var countryGuideButton: some View {
        Button {
            guideTopic = .overview
        } label: {
            Label("Country guide", systemImage: "book.closed")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(.white.opacity(0.15)))
                .overlay(alignment: .topTrailing) {
                    statusDots
                        .offset(x: 6, y: -6)
                }
        }
        .buttonStyle(.plain)
        .accessibilityValue(statusSummary)
        .animation(.easeInOut, value: travelStatuses.map(\.value))
    }

    /// Advisory, visa, health and disaster statuses for the selected country,
    /// in the order the dots show them.
    private var travelStatuses: [TravelStatus] {
        [
            TravelStatus.advisory(viewModel.advisoryStatus),
            TravelStatus.visa(viewModel.admissoryStatus, passport: viewModel.nationality),
            TravelStatus.health(viewModel.outbreakReports),
            TravelStatus.disasters(viewModel.disasterAlerts),
        ].compactMap { $0 }
    }

    /// The statuses' colours as small dots in a dark pill.
    @ViewBuilder
    private var statusDots: some View {
        let statuses = travelStatuses
        if !statuses.isEmpty {
            HStack(spacing: 3) {
                ForEach(statuses) { status in
                    CircularStatusView(colors: status.colors)
                        .frame(width: 10, height: 10)
                }
            }
            .padding(3)
            .background(Capsule().fill(.black.opacity(0.55)))
            .transition(.scale.combined(with: .opacity))
            .accessibilityHidden(true)
        }
    }

    /// "Travel advisory: Exercise normal security precautions. Visa: …" for
    /// VoiceOver.
    private var statusSummary: String {
        travelStatuses
            .map { "\($0.title): \($0.value)" }
            .joined(separator: ". ")
    }

    /// One banner for the most pressing thing happening in the country: an
    /// active disaster, an ongoing internet disruption, or a WHO outbreak
    /// report from the last 30 days. Tapping it opens the guide, which lists
    /// them all.
    private var cardAlert: (title: String, symbol: String, color: Color, accessibility: String, topic: DestinationGuide.Topic)? {
        if let alert = viewModel.disasterAlerts.first(where: \.isUrgent) {
            return (alert.name, alert.kind.symbolName, alert.level == .red ? .red : .orange, "\(alert.level.rawValue) alert: \(alert.name)", .climate)
        }
        if viewModel.internetOutages.contains(where: \.isOngoing) {
            return ("Internet disruption detected", "wifi.exclamationmark", .purple, "Internet disruption detected", .overview)
        }
        if let report = viewModel.outbreakReports.first,
           report.published > Date().addingTimeInterval(-30 * 24 * 60 * 60) {
            return ("Outbreak: \(report.disease)", "cross.case.fill", .orange, "Recent outbreak report: \(report.disease)", .health)
        }
        return nil
    }

    @ViewBuilder
    var alertBanner: some View {
        if let alert = cardAlert {
            Button {
                guideTopic = alert.topic
            } label: {
                Label(alert.title, systemImage: alert.symbol)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(alert.color.opacity(0.85)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(alert.accessibility)
            .accessibilityHint("Opens the country guide")
            .transition(.opacity)
        }
    }

    /// Weather and local time at the capital, and the exchange rate from the
    /// home currency, in one line under the country name.
    @ViewBuilder
    var liveInfoStrip: some View {
        let weather = viewModel.destinationWeather
        let rate = viewModel.exchangeRates.first
        if weather != nil || rate != nil {
            HStack(spacing: 14) {
                if let weather {
                    Label {
                        Text(DestinationWeather.temperatureText(weather.temperature))
                    } icon: {
                        Image(systemName: weather.symbolName)
                            .symbolRenderingMode(.multicolor)
                    }
                    .accessibilityLabel("\(weather.condition.description), \(DestinationWeather.temperatureText(weather.temperature))")
                    TimelineView(.everyMinute) { context in
                        Label {
                            Text(weather.localTime(at: context.date))
                        } icon: {
                            Image(systemName: "clock")
                        }
                        .accessibilityLabel("Local time")
                        .accessibilityValue(Text(weather.localTime(at: context.date)))
                    }
                }
                if let rate {
                    Label("1 \(rate.home) = \(ExchangeRate.format(rate.rate)) \(rate.destination)", systemImage: "banknote")
                }
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(.white.opacity(0.9))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .transition(.opacity)
        }
    }

    @ViewBuilder
    var bottomStack: some View {
        FloatingGlassGroup {
            VStack(spacing: 0) {
                HStack(alignment: .bottom, spacing: 15) {
                    randomCountryButton
                        // Slide off-screen while the country list is open,
                        // leaving the list as the only thing to interact with.
                        .offset(x: isPickingCountry ? -120 : 0)
                        .opacity(isPickingCountry ? 0 : 1)
                    Spacer()
                    if !isPickingCountry {
                        VStack(spacing: 6) {
                            flightsNotice
                            if showsEarthAtNight {
                                if let nightLightsDate {
                                    mapCredit("NASA GIBS · Black Marble\n\(nightLightsDate) UTC")
                                } else {
                                    mapCredit(nightLightsLoadFailed ? "Night lights unavailable" : "Loading night lights…")
                                }
                            }
                            if showsVIIRSImagery {
                                if let date = viirsImageryDate {
                                    mapCredit("NASA GIBS · VIIRS\n\(date) UTC")
                                } else {
                                    mapCredit(viirsLoadFailed ? "VIIRS imagery unavailable" : "Loading VIIRS dates…")
                                }
                            }
                        }
                    }
                    Spacer()
                    VStack(spacing: 12) {
                        layersButton
                        passportButton
                    }
                    .offset(x: isPickingCountry ? 120 : 0)
                    .opacity(isPickingCountry ? 0 : 1)
                }
                .animation(.easeInOut, value: viewModel.flightsPausedUntil == nil)
                .animation(.easeInOut, value: viewModel.isShowingSubsetOfFlights)
                .padding(.horizontal)
                .padding(.top)
                selectionButton
            }
        }
        // The container renders the glass, so it needs the dark appearance too.
        .environment(\.colorScheme, .dark)
        .sheet(isPresented: $showingNationalityPicker) {
            NationalityPickerView(countries: viewModel.countries, selection: $viewModel.nationality)
        }
    }

    private func mapCredit(_ credit: String) -> some View {
        Text(credit)
            .font(.caption2)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.65), in: Capsule())
    }

    private func updateVIIRSImageryDates() async {
        viirsLoadFailed = false
        do {
            let dates = try await viewModel.loadVIIRSImageryDates(for: .trueColour)
            guard !Task.isCancelled else { return }
            viirsDates = dates
            if let selectedVIIRSDate, !dates.contains(selectedVIIRSDate) {
                self.selectedVIIRSDate = nil
            }
        } catch {
            if !Task.isCancelled { viirsLoadFailed = true }
        }
    }

    private func updateNightLightsDate() async {
        nightLightsLoadFailed = false
        do {
            let dates = try await viewModel.loadVIIRSImageryDates(for: .nightLights)
            if !Task.isCancelled { nightLightsDate = dates.first }
        } catch {
            if !Task.isCancelled { nightLightsLoadFailed = true }
        }
    }

    /// Dims the map while the country list is open; tapping it closes the list.
    @ViewBuilder
    var countryListScrim: some View {
        if isPickingCountry {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(duration: 0.4)) {
                        isPickingCountry = false
                    }
                }
                .transition(.opacity)
                .accessibilityLabel("Close country list")
                .accessibilityAddTraits(.isButton)
        }
    }

    var randomCountryButton: some View {
        Button {
            viewModel.selectRandomCountry()
        } label: {
            Image(systemName: "globe.americas.fill")
                .font(.title3)
                .foregroundStyle(.white)
                .symbolEffect(.variableColor, options: .nonRepeating, value: viewModel.current)
                .frame(width: 50, height: 50)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .floatingGlass(in: Circle(), interactive: true)
        .environment(\.colorScheme, .dark)
        .accessibilityLabel("Random country")
    }

    /// Opens the passport picker. Shows the chosen passport's flag as a badge.
    /// Switches map layers on and off.
    var layersButton: some View {
        Menu {
            Toggle(isOn: $viewModel.showsFlights) {
                Label("Live flights", systemImage: "airplane")
            }
            Toggle(isOn: $viewModel.showsHazards) {
                Label("Natural hazards", systemImage: "exclamationmark.triangle")
            }
            Toggle(isOn: $viewModel.showsCables) {
                Label("Undersea cables", systemImage: "cable.connector")
            }
            Toggle(isOn: $showsEarthAtNight) {
                Label("Earth at night", systemImage: "circle.lefthalf.filled")
            }
            Toggle(isOn: $showsVIIRSImagery) {
                Label("VIIRS true colour", systemImage: "camera")
            }
            if showsVIIRSImagery, !viirsDates.isEmpty {
                Picker("VIIRS imagery date (UTC)", selection: $selectedVIIRSDate) {
                    Text("Latest available").tag(nil as String?)
                    ForEach(viirsDates, id: \.self) { date in
                        Text(date).tag(Optional(date))
                    }
                }
                .pickerStyle(.menu)
            }
        } label: {
            Image(systemName: "square.3.layers.3d")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .contentShape(Circle())
        }
        .menuOrder(.fixed)
        .floatingGlass(in: Circle(), interactive: true)
        .environment(\.colorScheme, .dark)
        .accessibilityLabel("Map layers")
    }

    var passportButton: some View {
        Button {
            showingNationalityPicker = true
        } label: {
            Image("passport-icon")
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 28)
                .frame(width: 50, height: 50)
                .overlay(alignment: .bottomTrailing) {
                    if let flag = viewModel.nationality?.flagURL {
                        AsyncFlagView(flag: flag, size: CGSize(width: 18, height: 12))
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                            .offset(x: -6, y: -8)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .floatingGlass(in: Circle(), interactive: true)
        .environment(\.colorScheme, .dark)
        .accessibilityLabel("Your passport")
        .accessibilityValue(viewModel.nationality?.name?.common ?? "Not set")
    }

    /// Explains why some or all aircraft are missing from the map: OpenSky is
    /// rate limiting us, or there are more flights than we draw at once.
    @ViewBuilder
    var flightsNotice: some View {
        if let pausedUntil = viewModel.flightsPausedUntil {
            noticeCapsule {
                // OpenSky's daily quota can pause us until the next day.
                if Calendar.current.isDateInToday(pausedUntil) {
                    Text("Live flights paused until \(pausedUntil, style: .time)")
                } else {
                    Text("Live flights paused until \(pausedUntil, format: .dateTime.weekday(.wide).hour().minute())")
                }
            }
        } else if viewModel.isShowingSubsetOfFlights {
            noticeCapsule {
                Text("\(viewModel.flightAnnotations.count, format: .number) of \(viewModel.totalFlightCount, format: .number) flights\nZoom in for more")
            }
        }
    }

    func noticeCapsule(@ViewBuilder text: () -> some View) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "airplane")
            text()
                // Wrap onto more lines rather than truncating or spilling out.
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote)
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        // A capsule's ends are as round as it is tall, so wrapped text would
        // poke out of a tall one. This matches a capsule on one line and
        // still fits several.
        .floatingGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .layoutPriority(1)
        .environment(\.colorScheme, .dark)
        .transition(.opacity)
        .accessibilityElement(children: .combine)
    }
    
    @ViewBuilder
    var selectionButton: some View {
        ExpandableSelectionButton(
            selectables: viewModel.countries,
            selected: $viewModel.current,
            isExpanded: $isPickingCountry,
            searchPrompt: "Search countries",
            matches: { country, query in
                [country.name?.common, country.name?.official]
                    .contains { $0?.localizedStandardContains(query) == true }
            },
            isExactMatch: { country, query in
                country.name?.common?.compare(query, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }
        ) { country in
            if let flag = country.flagURL, let name = country.name?.common {
                AsyncFlagView(flag: flag)
                Spacer()
                Text(name)
                    .tint(.white)
                Spacer()
            }
        }
    }
}

/// Details for the selected aircraft: its route and photo from adsbdb.com,
/// live values from OpenSky or, for military aircraft, adsb.lol (updated on
/// every poll) and its registration.
struct FlightDetailsView: View {

    var viewModel: MainMapViewModel
    /// Kept by the sheet, so the content stays put while it's dismissed and
    /// the selection has already been cleared.
    let flightID: String

    @Environment(\.dismiss) private var dismiss

    private var flight: LiveFlight? { viewModel.flight(for: flightID) }
    private var aircraft: AircraftInfo? { viewModel.selectedAircraft }

    private var position: CLLocation? {
        flight.map { CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
    }

    private var title: String {
        flight?.callsign ?? flight?.registration ?? aircraft?.registration ?? flightID.uppercased()
    }

    /// Kept once known, so the footer doesn't change if the aircraft drops
    /// out of the feed while the sheet is open.
    @State private var wasMilitary = false
    private var isMilitary: Bool { flight?.isMilitary ?? wasMilitary }

    var body: some View {
        NavigationStack {
            List {
                if let photo = aircraft?.urlPhoto.flatMap(URL.init(string:)) {
                    photoSection(photo)
                }
                routeSection
                liveSection
                aircraftSection
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        if isMilitary, let url = URL(string: "https://globe.adsb.lol/?icao=\(flightID)") {
                            Link("Track on adsb.lol", destination: url)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.blue)
                        }
                        Text(isMilitary
                             ? "Military aircraft. Live position from adsb.lol, a community network of ADS-B receivers (ODbL); only aircraft that broadcast a position are shown. Aircraft and route from adsbdb.com, which is community-maintained and may be incomplete."
                             : "Live position from The OpenSky Network. Aircraft and route from adsbdb.com, which is community-maintained and may be incomplete.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onChange(of: flight?.isMilitary, initial: true) { _, isMilitary in
                if let isMilitary { wasMilitary = isMilitary }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(uiColor: .systemGroupedBackground))
        .preferredColorScheme(.dark)
    }

    // MARK: Sections

    private func photoSection(_ url: URL) -> some View {
        Section {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Color.secondary.opacity(0.15)
                    .overlay(ProgressView())
            }
            .frame(height: 190)
            .frame(maxWidth: .infinity)
            .clipped()
            .listRowInsets(EdgeInsets())
        } footer: {
            Text("Photo: airport-data.com")
        }
    }

    @ViewBuilder
    private var routeSection: some View {
        Section("Route") {
            if let route = viewModel.selectedRoute {
                VStack(spacing: 14) {
                    HStack(alignment: .center) {
                        airport(route.origin, alignment: .leading)
                        Spacer()
                        // The map marker, turned to fly from origin to destination.
                        Image("aircraft")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 32, height: 32)
                            .rotationEffect(.degrees(90))
                            .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                            .accessibilityHidden(true)
                        Spacer()
                        airport(route.destination, alignment: .trailing)
                    }
                    if let position {
                        let progress = route.progress(forAircraftAt: position)
                        ProgressView(value: progress.fraction)
                        HStack {
                            Text("\(distanceText(progress.flown)) flown")
                            Spacer()
                            Text("\(distanceText(progress.remaining)) to go")
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
                if let airline = route.airline?.name {
                    LabeledContent("Airline", value: airline)
                }
                if let flightNumber = route.callsignIata, flightNumber != route.callsign {
                    LabeledContent("Flight number", value: flightNumber)
                }
            } else if viewModel.isLoadingFlightDetails {
                loadingRow
            } else {
                Text("Route not available")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var liveSection: some View {
        Section("Live") {
            if let flight {
                if flight.isMilitary {
                    Label("Military aircraft", systemImage: "shield.lefthalf.filled")
                        .foregroundStyle(Color(uiColor: .militaryAircraft))
                }
                if let emergency = flight.emergency {
                    Label("Emergency: \(emergency)", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
                if let altitude = flight.altitudeMeters, !flight.isOnGround {
                    LabeledContent("Altitude", value: altitudeText(meters: altitude))
                }
                if let speed = flight.speedMetersPerSecond {
                    LabeledContent("Speed", value: speedText(metersPerSecond: speed))
                }
                if let track = flight.track {
                    LabeledContent("Heading", value: Self.headingText(degrees: track))
                }
                if flight.isOnGround {
                    LabeledContent("Status", value: "On the ground")
                } else if let verticalRate = flight.verticalRateMetersPerSecond {
                    LabeledContent("Vertical speed", value: verticalRateText(metersPerSecond: verticalRate))
                }
                if let squawk = flight.squawk {
                    squawkRow(squawk)
                }
                LabeledContent("Last update") {
                    Text("\(flight.lastContact, style: .relative) ago")
                }
            } else {
                Text("No live data for this flight right now.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var aircraftSection: some View {
        Section("Aircraft") {
            if let type = aircraft?.displayType {
                LabeledContent("Type", value: type)
            } else if let code = flight?.typeCode {
                LabeledContent("Type code", value: code)
            }
            if let registration = aircraft?.registration ?? flight?.registration {
                LabeledContent("Registration", value: registration)
            }
            if let owner = aircraft?.registeredOwner {
                LabeledContent("Operator", value: owner)
            }
            if let country = aircraft?.registeredOwnerCountryName ?? flight?.originCountry {
                LabeledContent("Registered in", value: country)
            }
            LabeledContent("ICAO address", value: flightID.uppercased())
            if aircraft == nil, viewModel.isLoadingFlightDetails {
                loadingRow
            }
        }
    }

    // MARK: Pieces

    private func airport(_ airport: FlightRoute.Airport, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(airport.code)
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
            Text(airport.municipality ?? airport.name)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private var loadingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Looking up…")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func squawkRow(_ squawk: String) -> some View {
        // Codes pilots set to signal trouble.
        let emergency = ["7500": "Hijack", "7600": "Radio failure", "7700": "Emergency"][squawk]
        LabeledContent("Squawk") {
            Text(emergency.map { "\(squawk) · \($0)" } ?? squawk)
                .foregroundStyle(emergency == nil ? Color.secondary : Color.red)
        }
    }

    // MARK: Formatting

    private func altitudeText(meters: Double) -> String {
        let altitude = Measurement(value: meters, unit: UnitLength.meters)
        let feet = altitude.converted(to: .feet).value.formatted(.number.precision(.fractionLength(0)))
        let metres = altitude.value.formatted(.number.precision(.fractionLength(0)))
        return "\(feet) ft · \(metres) m"
    }

    private func speedText(metersPerSecond: Double) -> String {
        let speed = Measurement(value: metersPerSecond, unit: UnitSpeed.metersPerSecond)
        let kilometers = speed.converted(to: .kilometersPerHour).value.formatted(.number.precision(.fractionLength(0)))
        let knots = speed.converted(to: .knots).value.formatted(.number.precision(.fractionLength(0)))
        return "\(kilometers) km/h · \(knots) kn"
    }

    /// "178° S".
    private static func headingText(degrees: Double) -> String {
        let points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((degrees.truncatingRemainder(dividingBy: 360) + 22.5) / 45) % points.count
        return "\(Int(degrees.rounded()))° \(points[index])"
    }

    private func verticalRateText(metersPerSecond: Double) -> String {
        let feetPerMinute = metersPerSecond * 196.85
        let rate = abs(feetPerMinute).formatted(.number.precision(.fractionLength(0)))
        if abs(feetPerMinute) < 100 { return "Level" }
        return feetPerMinute > 0 ? "Climbing \(rate) ft/min" : "Descending \(rate) ft/min"
    }

    private func distanceText(_ meters: CLLocationDistance) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .converted(to: .kilometers)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))))
    }
}

/// Searchable list for choosing the passport you travel on, which decides the
/// visa requirement shown for each destination.
struct NationalityPickerView: View {

    let countries: [Country]
    @Binding var selection: Country?

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var matches: [Country] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return countries }
        return countries.filter { $0.name?.common?.localizedStandardContains(query) == true }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(matches) { country in
                        Button {
                            selection = country
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                AsyncFlagView(flag: country.flagURL, size: CGSize(width: 36, height: 24))
                                Text(country.name?.common ?? "")
                                Spacer()
                                if country.cca2 == selection?.cca2 {
                                    Image(systemName: "checkmark")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.blue)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        // Rows read as a list of names, not as links.
                        .tint(.primary)
                        .accessibilityAddTraits(country.cca2 == selection?.cca2 ? .isSelected : [])
                    }
                } header: {
                    Text("Choose the passport you travel on to see visa requirements for each country.")
                        .textCase(nil)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search countries")
            .navigationTitle("Your passport")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(uiColor: .systemGroupedBackground))
        .preferredColorScheme(.dark)
    }
}
