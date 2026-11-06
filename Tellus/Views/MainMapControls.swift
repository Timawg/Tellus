import SwiftUI

struct MainMapControls: View {
    @Bindable var viewModel: MainMapViewModel
    @Bindable var gpsJam: GPSJAMLayerState
    @Binding var isPickingCountry: Bool
    @Binding var selectedVIIRSDate: String?
    let viirsDates: [String]
    @State private var showingNationalityPicker = false

    @ViewBuilder
    var body: some View {
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

                            if viewModel.showsGPSJAM {
                                GPSJAMLegend(state: gpsJam)
                            }
                            if viewModel.showsPowerGrid {
                                powerGridCredit
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

    private var powerGridCredit: some View {
        VStack(spacing: 3) {
            HStack(spacing: 5) {
                Text("Lines").foregroundStyle(Color(cgColor: PowerGridAsset.Kind.line.color))
                Text("Substations").foregroundStyle(Color(cgColor: PowerGridAsset.Kind.substation.color))
                Text("Plants").foregroundStyle(Color(cgColor: PowerGridAsset.Kind.plant.color))
            }
            Link("© OpenStreetMap contributors", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
        }
        .font(.caption2)
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 9))
    }

    private var randomCountryButton: some View {
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

    /// Switches map layers on and off.
    private var layersButton: some View {
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
            Toggle(isOn: $viewModel.showsPowerGrid) {
                Label("Power grid", systemImage: "bolt")
            }
            Toggle(isOn: $viewModel.showsGPSJAM) {
                Label("GPS interference", systemImage: "location.slash")
            }
            if viewModel.showsGPSJAM {
                Picker("GPSJAM date (UTC)", selection: $gpsJam.selectedDay) {
                    Text("Latest available").tag(nil as Date?)
                    ForEach(gpsJam.selectableDays, id: \.self) { day in
                        Text(GPSJAMService.dayLabel(day)).tag(Optional(day))
                    }
                }
                .pickerStyle(.menu)
            }
            Toggle(isOn: $viewModel.showsEarthAtNight) {
                Label("Earth at night", systemImage: "circle.lefthalf.filled")
            }
            Toggle(isOn: $viewModel.showsVIIRSImagery) {
                Label("VIIRS true colour", systemImage: "camera")
            }
            if viewModel.showsVIIRSImagery, !viirsDates.isEmpty {
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

    /// Shows the chosen passport's flag as a badge.
    private var passportButton: some View {
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
    private var flightsNotice: some View {
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

    private func noticeCapsule(@ViewBuilder text: () -> some View) -> some View {
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
    private var selectionButton: some View {
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
