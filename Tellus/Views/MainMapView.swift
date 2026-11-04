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
    @State private var showingLocalLaws = false

    var body: some View {
        MapRepresentable(
            region: $viewModel.region,
            selectedAnnotation: $viewModel.selectedFlight,
            annotations: viewModel.flightAnnotations
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
        .overlay(alignment: .bottom) {
            bottomStack
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
        }.onChange(of: viewModel.nationality) { oldValue, newValue in
            viewModel.persist(nationality: newValue)
            Task {
                await viewModel.updateAdmissoryStatus()
            }
        }
        .sheet(item: $viewModel.selectedFlight) {
            viewModel.selectedFlight = nil
        } content: { identifiable in
            ListView(viewModel: viewModel)
                .presentationDetents([.fraction(0.25), .medium])
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
                if !viewModel.localLaws.isEmpty {
                    Button {
                        showingLocalLaws = true
                    } label: {
                        Label("Local laws & culture", systemImage: "building.columns")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(.white.opacity(0.15)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .sheet(isPresented: $showingLocalLaws) {
                if let information = viewModel.advisoryStatus?.data.eng {
                    LocalLawsView(countryName: name, information: information, sections: viewModel.localLaws)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(.white.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }
    
    @ViewBuilder
    var bottomStack: some View {
        VStack {
            HStack(spacing: 15) {
                LinearGradient(colors: [.tellusDark, .tellusLight], startPoint: .top, endPoint: .bottom)
                    .frame(width: 50, height: 50, alignment: .center)
                    .clipShape(.rect(cornerSize: .init(width: 50, height: 50)))
                    .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 2)
                    .overlay {
                        Image(systemName: "globe.americas.fill")
                            .renderingMode(.template)
                            .foregroundColor(.white)
                            .symbolEffect(.variableColor, options: .nonRepeating, value: viewModel.current)
                    }.onTapGesture {
                        viewModel.selectRandomCountry()
                    }
                Spacer()
                flightsNotice
                Spacer()
                LinearGradient(colors: [.tellusDark, .tellusLight], startPoint: .top, endPoint: .bottom)
                    .frame(width: 50, height: 50, alignment: .center)
                    .clipShape(.rect(cornerSize: .init(width: 50, height: 50)))
                    .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 2)
                    .overlay {
                        AsyncFlagView(flag: viewModel.nationality?.flagURL)
                        Image("passport-icon")
                            .resizable()
                            .frame(maxWidth: 25, maxHeight: 30, alignment: .center)
                        Picker("Select Country", selection: $viewModel.nationality) {
                            Text(viewModel.nationality?.name?.common ?? "").hidden().tag(viewModel.nationality)
                            ForEach(viewModel.countries, id: \.self) { country in
                                HStack(alignment: .center, spacing: 8) {
                                    if let name = country.name?.common {
                                        Text(name)
                                    }
                                }.tag(Optional(country))
                            }
                        }
                    }.onTapGesture {
                        viewModel.updateRegion()
                    }
            }
            .animation(.easeInOut, value: viewModel.flightsPausedUntil == nil)
            .animation(.easeInOut, value: viewModel.isShowingSubsetOfFlights)
            .padding()
            selectionButton
        }
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
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .overlay(
            Capsule()
                .strokeBorder(.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        .transition(.opacity)
        .accessibilityElement(children: .combine)
    }
    
    @ViewBuilder
    var selectionButton: some View {
        ExpandableSelectionButton(selectables: viewModel.countries, selected: $viewModel.current) { country in
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

struct ListView: View {
    
    var viewModel: MainMapViewModel
    
    @ViewBuilder
    func infoStack(description: String, value: String) -> some View {
        HStack {
            Text(description)
            Spacer()
            Text(value)
        }
        .foregroundStyle(.white)
    }
    
    private func velocityText(metersPerSecond: Float) -> String {
        let speedInMetersPerSecond = Measurement(value: Double(metersPerSecond), unit: UnitSpeed.metersPerSecond)
        let speedInKilometersPerHour = speedInMetersPerSecond.converted(to: .kilometersPerHour)
        let formatter = MeasurementFormatter()
        formatter.unitStyle = .short
        return formatter.string(from: speedInKilometersPerHour)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [.tellusLight, .tellusDark]),
                startPoint: .top,
                endPoint: .bottom
            )
            .edgesIgnoringSafeArea(.all)
            
            VStack(alignment: .leading, spacing: 8) {
                    infoStack(description: "Origin Country:", value: viewModel.selectedState?.originCountry ?? "")
                if let latitude = viewModel.selectedState?.latitude {
                    infoStack(description: "Latitude:", value: "\(latitude) °")
                }
                if let longitude = viewModel.selectedState?.longitude {
                    infoStack(description: "Longitude:", value: "\(longitude) °")
                }
                if let trueTrack = viewModel.selectedState?.trueTrack {
                    infoStack(description:"True Track:" , value: "\(trueTrack)°")
                }
                if let velocity = viewModel.selectedState?.velocity {
                    infoStack(description: "Velocity:", value: velocityText(metersPerSecond: velocity))
                }
                if let geoAltitude = viewModel.selectedState?.geoAltitude {
                    infoStack(description: "Altitude:", value: "\(geoAltitude) meters")
                }
            }
            .background(.clear)
            .padding()
        }
    }
}

/// The destination's laws and culture advice from the Canadian government,
/// with each topic (Drugs, Driving, …) collapsed so the list is easy to scan.
struct LocalLawsView: View {

    let countryName: String
    let information: Information
    let sections: [LawSection]

    @Environment(\.dismiss) private var dismiss

    private var introduction: LawSection? {
        sections.first { $0.title == nil }
    }

    private var topics: [LawSection] {
        sections.filter { $0.title != nil }
    }

    var body: some View {
        NavigationStack {
            List {
                if let introduction {
                    Section("Laws & culture") {
                        blocks(introduction.blocks)
                    }
                }
                if !topics.isEmpty {
                    Section(introduction == nil ? "Laws & culture" : "Topics") {
                        ForEach(topics) { topic in
                            DisclosureGroup {
                                blocks(topic.blocks)
                                    .padding(.vertical, 4)
                            } label: {
                                Text(topic.title ?? "")
                                    .font(.body.weight(.semibold))
                            }
                        }
                    }
                }
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Advice from the Government of Canada, written for Canadian travellers. Updated \(information.friendlyDate).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if let url = information.travelAdviceURL {
                            Link("Read the full advice on travel.gc.ca", destination: url)
                                .font(.footnote.weight(.semibold))
                        }
                    }
                }
            }
            .navigationTitle(countryName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        // Solid, so the colourful map doesn't show through behind long text.
        .presentationBackground(Color(uiColor: .systemGroupedBackground))
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func blocks(_ blocks: [LawSection.Block]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let text):
                    Text(text)
                case .bullet(let text):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                        Text(text)
                    }
                    .padding(.leading, 4)
                case .subheading(let text):
                    Text(text)
                        .font(.subheadline.weight(.semibold))
                        .padding(.top, 4)
                }
            }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
