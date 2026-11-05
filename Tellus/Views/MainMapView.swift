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
    @State private var showingDestinationGuide = false
    @State private var showingNationalityPicker = false
    @State private var isPickingCountry = false

    var body: some View {
        MapRepresentable(
            region: $viewModel.region,
            selectedAnnotation: $viewModel.selectedFlight,
            annotations: viewModel.flightAnnotations,
            cables: viewModel.cables,
            landingPoints: viewModel.landingPoints,
            selectedCableID: viewModel.selectedCableID,
            selectCable: { viewModel.selectedCableID = $0 }
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
        }.task {
            await viewModel.loadCablesIfNeeded()
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
                HStack(alignment: .center, spacing: 8) {
                    AsyncFlagView(flag: flag)
                    Text(name)
                        .font(.headline)
                }
                liveInfoStrip
                alertBanner
                if let status = viewModel.advisoryStatus {
                    HStack {
                        CircularStatusView(colors: status.colors)
                            .frame(width: 20, height: 20, alignment: .center)
                        Text(status.data.eng.advisoryText)
                            .animation(.some(.easeIn), value: status)
                            .multilineTextAlignment(.center)
                    }
                }
                if let status = viewModel.admissoryStatus {
                    HStack {
                        CircularStatusView(colors: status.colors)
                            .frame(width: 20, height: 20, alignment: .center)
                        Text(status.category.capitalized)
                            .animation(.some(.easeIn), value: status)
                            .multilineTextAlignment(.center)
                    }
                }
                Button {
                    showingDestinationGuide = true
                } label: {
                    Label("Destination guide", systemImage: "book.closed")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(.white.opacity(0.15)))
                }
                .buttonStyle(.plain)
            }
            .sheet(isPresented: $showingDestinationGuide) {
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
    
    /// One banner for the most pressing thing happening in the country: an
    /// active disaster, an ongoing internet disruption, or a WHO outbreak
    /// report from the last 30 days. Tapping it opens the guide, which lists
    /// them all.
    private var cardAlert: (title: String, symbol: String, color: Color, accessibility: String)? {
        if let alert = viewModel.disasterAlerts.first(where: \.isUrgent) {
            return (alert.name, alert.kind.symbolName, alert.level == .red ? .red : .orange, "\(alert.level.rawValue) alert: \(alert.name)")
        }
        if viewModel.internetOutages.contains(where: \.isOngoing) {
            return ("Internet disruption detected", "wifi.exclamationmark", .purple, "Internet disruption detected")
        }
        if let report = viewModel.outbreakReports.first,
           report.published > Date().addingTimeInterval(-30 * 24 * 60 * 60) {
            return ("Outbreak: \(report.disease)", "cross.case.fill", .orange, "Recent outbreak report: \(report.disease)")
        }
        return nil
    }

    @ViewBuilder
    var alertBanner: some View {
        if let alert = cardAlert {
            Button {
                showingDestinationGuide = true
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
            .accessibilityHint("Opens the destination guide")
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
                        flightsNotice
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
            Toggle(isOn: $viewModel.showsCables) {
                Label("Undersea cables", systemImage: "cable.connector")
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
                        AsyncFlagView(flag: flag)
                            .frame(width: 18, height: 12)
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
                Text("Live flights paused until \(pausedUntil, style: .time)")
            }
        } else if viewModel.isShowingSubsetOfFlights {
            noticeCapsule {
                Text("\(viewModel.flightAnnotations.count, format: .number) of \(viewModel.totalFlightCount, format: .number) flights\nZoom in for more")
            }
        }
    }

    func noticeCapsule(@ViewBuilder text: () -> some View) -> some View {
        Label {
            text()
        } icon: {
            Image(systemName: "airplane")
        }
        .font(.footnote)
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .floatingGlass(in: Capsule())
        .environment(\.colorScheme, .dark)
        .transition(.opacity)
        .accessibilityElement(children: .combine)
    }
    
    @ViewBuilder
    var selectionButton: some View {
        ExpandableSelectionButton(
            selectables: viewModel.countries,
            selected: $viewModel.current,
            isExpanded: $isPickingCountry
        ) { country in
            if let flag = country.flagURL, let name = country.name?.common {
                AsyncFlagView(flag: flag)
                    .frame(minWidth: 40, minHeight: 25)
                Spacer()
                Text(name)
                    .tint(.white)
                Spacer()
            }
        }
    }
}

/// Details for the selected aircraft: its route and photo from adsbdb.com,
/// live values from OpenSky (updated on every poll) and its registration.
struct FlightDetailsView: View {

    var viewModel: MainMapViewModel
    /// Kept by the sheet, so the content stays put while it's dismissed and
    /// the selection has already been cleared.
    let flightID: String

    @Environment(\.dismiss) private var dismiss

    private var state: StateVector? { viewModel.state(for: flightID) }
    private var aircraft: AircraftInfo? { viewModel.selectedAircraft }

    private var position: CLLocation? {
        guard let latitude = state?.latitude, let longitude = state?.longitude else { return nil }
        return CLLocation(latitude: CLLocationDegrees(latitude), longitude: CLLocationDegrees(longitude))
    }

    private var title: String {
        if let callsign = state?.callsign?.trimmingCharacters(in: .whitespaces), !callsign.isEmpty {
            return callsign
        }
        return aircraft?.registration ?? flightID.uppercased()
    }

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
                    Text("Live position from The OpenSky Network. Aircraft and route from adsbdb.com, which is community-maintained and may be incomplete.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
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
                    HStack(alignment: .top) {
                        airport(route.origin, alignment: .leading)
                        Spacer()
                        Image(systemName: "airplane")
                            .font(.title2)
                            .foregroundStyle(.tint)
                            .padding(.top, 8)
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
            if let state {
                if let altitude = state.geoAltitude ?? state.baroAltitude {
                    LabeledContent("Altitude", value: altitudeText(meters: altitude))
                }
                if let velocity = state.velocity {
                    LabeledContent("Speed", value: speedText(metersPerSecond: velocity))
                }
                if let track = state.trueTrack {
                    LabeledContent("Heading", value: headingText(degrees: track))
                }
                if state.onGround {
                    LabeledContent("Status", value: "On the ground")
                } else if let verticalRate = state.verticalRate {
                    LabeledContent("Vertical speed", value: verticalRateText(metersPerSecond: verticalRate))
                }
                if let squawk = state.squawk {
                    squawkRow(squawk)
                }
                LabeledContent("Last update") {
                    Text("\(Date(timeIntervalSince1970: TimeInterval(state.lastContact)), style: .relative) ago")
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
            }
            if let registration = aircraft?.registration {
                LabeledContent("Registration", value: registration)
            }
            if let owner = aircraft?.registeredOwner {
                LabeledContent("Operator", value: owner)
            }
            if let country = aircraft?.registeredOwnerCountryName ?? state?.originCountry {
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

    private func altitudeText(meters: Float) -> String {
        let altitude = Measurement(value: Double(meters), unit: UnitLength.meters)
        let feet = altitude.converted(to: .feet).value.formatted(.number.precision(.fractionLength(0)))
        let metres = altitude.value.formatted(.number.precision(.fractionLength(0)))
        return "\(feet) ft · \(metres) m"
    }

    private func speedText(metersPerSecond: Float) -> String {
        let speed = Measurement(value: Double(metersPerSecond), unit: UnitSpeed.metersPerSecond)
        let kilometers = speed.converted(to: .kilometersPerHour).value.formatted(.number.precision(.fractionLength(0)))
        let knots = speed.converted(to: .knots).value.formatted(.number.precision(.fractionLength(0)))
        return "\(kilometers) km/h · \(knots) kn"
    }

    private func headingText(degrees: Float) -> String {
        let points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((Double(degrees) + 22.5) / 45) % points.count
        return "\(Int(degrees.rounded()))° \(points[index])"
    }

    private func verticalRateText(metersPerSecond: Float) -> String {
        let feetPerMinute = Double(metersPerSecond) * 196.85
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
                                AsyncFlagView(flag: country.flagURL)
                                    .frame(width: 36, height: 24)
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
