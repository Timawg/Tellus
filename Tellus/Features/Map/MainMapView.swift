//
//  MainMapView.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2023-09-14.
//

import SwiftUI
import MapKit

struct MainMapView: View {

    @Bindable var viewModel: MainMapViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var gpsJam = GPSJAMLayerState()
    @State private var aurora = AuroraLayerState()
    @State private var selectedPowerAsset: PowerGridAsset?
    @State private var viirsDates: [String] = []
    @State private var selectedVIIRSDate: String?
    @State private var nightLightsDate: String?
    @State private var isPickingCountry = false

    private var viirsImageryDate: String? {
        guard viewModel.showsVIIRSImagery else { return nil }
        return selectedVIIRSDate ?? viirsDates.first
    }

    private var gpsJamRequest: GPSJAMLayerState.Request {
        .init(isActive: viewModel.showsGPSJAM && scenePhase == .active, day: gpsJam.selectedDay)
    }

    var body: some View {
        @Bindable var flights = viewModel.flights
        @Bindable var hazards = viewModel.hazardLayer
        let cables = viewModel.cableLayer

        MapRepresentable(
            region: $viewModel.region,
            selectedFlightID: $flights.selectedFlightID,
            flightMarkers: flights.markerSnapshot,
            showsEarthAtNight: viewModel.showsEarthAtNight,
            nightLightsDate: nightLightsDate,
            viirsImageryDate: viirsImageryDate,
            auroraOverlay: viewModel.showsAurora ? aurora.overlay : nil,
            showsPowerGrid: viewModel.showsPowerGrid,
            selectPowerAsset: { selectedPowerAsset = $0 },
            gpsJamOverlay: viewModel.showsGPSJAM ? gpsJam.overlay : nil,
            selectGPSJAMCell: { gpsJam.selectedCell = $0 },
            cables: cables.cables,
            landingPoints: cables.landingPoints,
            selectedCableID: cables.selectedCableID,
            selectCable: cables.selectCable,
            tapCountry: { coordinate in
                Task { await viewModel.selectCountry(at: coordinate) }
            },
            outline: viewModel.selectedBorder,
            hazards: hazards.hazards,
            cycloneTracks: hazards.tracks,
            selectHazard: hazards.selectHazard(id:)
        ) {
            flights.viewportWillChange()
        } regionDidChange: { rect in
            viewModel.updateViewport(rect)
        }
        .edgesIgnoringSafeArea([.top,.bottom])
        .overlay(alignment: .top) {
            CountrySummaryView(
                country: viewModel.current,
                passport: viewModel.nationality,
                model: viewModel.countryGuide,
                neighbours: viewModel.neighbours(of:),
                selectCountry: { viewModel.current = $0 }
            )
        }
        .overlay {
            countryListScrim
        }
        .overlay(alignment: .bottom) {
            MainMapControls(
                viewModel: viewModel,
                flights: flights,
                gpsJam: gpsJam,
                aurora: aurora,
                isPickingCountry: $isPickingCountry,
                selectedVIIRSDate: $selectedVIIRSDate,
                viirsDates: viirsDates
            )
        }
        .task(id: gpsJamRequest) { [request = gpsJamRequest] in
            await gpsJam.load(request, fetch: viewModel.loadGPSJAMOverlay(for:))
        }
        .task(id: viewModel.showsAurora && scenePhase == .active) {
            guard viewModel.showsAurora, scenePhase == .active else { return }
            await aurora.refreshWhileActive(fetch: viewModel.loadAuroraForecast)
        }
        .task(id: viewModel.showsVIIRSImagery && scenePhase == .active) {
            guard viewModel.showsVIIRSImagery, scenePhase == .active else { return }
            await updateVIIRSImageryDates()
        }
        .task(id: viewModel.showsEarthAtNight && scenePhase == .active) {
            guard viewModel.showsEarthAtNight, scenePhase == .active else { return }
            await updateNightLightsDate()
        }
        .task(id: cables.activationID) { [activation = cables.activationID] in
            await cables.load(for: activation)
        }
        .task(id: cables.selectedCableID) { [id = cables.selectedCableID] in
            await cables.loadSelectedDetails(for: id)
        }
        .task(id: hazards.activationID) { [activation = hazards.activationID] in
            await hazards.refreshWhileEnabled(for: activation)
        }
        .task {
            await viewModel.retrieveCountries()
        }
        .task(id: viewModel.current?.id) {
            await viewModel.refreshDestination()
        }
        .task(id: viewModel.countryGuide.travelSelection) { [destination = viewModel.current, passport = viewModel.nationality] in
            await viewModel.countryGuide.refreshPassportInformation(destination: destination, passport: passport)
        }
        .task(id: flights.selectedFlightID) {
            await flights.loadFlightDetails()
        }
        .onAppear {
            flights.setMapActive(scenePhase == .active)
        }
        .onChange(of: scenePhase) { _, phase in
            flights.setMapActive(phase == .active)
        }
        .onDisappear {
            flights.setMapActive(false)
        }
        .sheet(isPresented: .init(
            get: { cables.selectedCableID != nil },
            set: { if !$0 { cables.selectCable(nil) } }
        )) {
            if let cable = cables.selectedCable {
                CableDetailsView(cable: cable, details: cables.selectedCableDetails)
            }
        }
        .sheet(item: $hazards.selectedHazard) { hazard in
            HazardDetailsView(hazard: hazard)
        }
        .sheet(item: Binding(get: { gpsJam.selectedCell }, set: { gpsJam.selectedCell = $0 })) { cell in
            GPSJAMCellDetails(cell: cell)
        }
        .sheet(item: $selectedPowerAsset) { asset in
            PowerAssetDetailsView(asset: asset)
        }
        .sheet(item: $flights.selection) { selection in
            FlightDetailsView(flights: flights, flightID: selection.id)
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

    private func updateVIIRSImageryDates() async {
        guard let dates = try? await viewModel.loadVIIRSImageryDates(for: .trueColour),
              !Task.isCancelled else { return }
        viirsDates = dates
        if let selectedVIIRSDate, !dates.contains(selectedVIIRSDate) {
            self.selectedVIIRSDate = nil
        }
    }

    private func updateNightLightsDate() async {
        guard let dates = try? await viewModel.loadVIIRSImageryDates(for: .nightLights),
              !Task.isCancelled else { return }
        nightLightsDate = dates.first
    }

    /// Dims the map while the country list is open; tapping it closes the list.
    @ViewBuilder
    private var countryListScrim: some View {
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
}
