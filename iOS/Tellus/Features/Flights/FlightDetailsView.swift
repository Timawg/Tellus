import SwiftUI
import MapKit

/// Details for the selected aircraft: its route and photo from adsbdb.com,
/// live values from OpenSky or, for military aircraft, adsb.lol (updated on
/// every poll) and its registration.
struct FlightDetailsView: View {

    let flights: LiveFlightsModel
    /// Kept by the sheet, so the content stays put while it's dismissed and
    /// the selection has already been cleared.
    let flightID: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var detents: Set<PresentationDetent> {
        if horizontalSizeClass == .compact || verticalSizeClass == .compact {
            return [.fraction(0.34), .medium, .large]
        }
        return [.medium, .large]
    }

    private var flight: LiveFlight? { flights.flight(for: flightID) }
    private var aircraft: AircraftInfo? { flights.selectedAircraft }

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
                routeSection
                if let photo = aircraft?.urlPhoto.flatMap(URL.init(string:)) {
                    photoSection(photo)
                }
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
        .presentationDetents(detents)
        .presentationCompactAdaptation(.sheet)
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
            if let route = flights.selectedRoute {
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
            } else if flights.isLoadingFlightDetails {
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
            if aircraft == nil, flights.isLoadingFlightDetails {
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
