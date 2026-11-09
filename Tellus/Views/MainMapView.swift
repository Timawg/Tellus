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
        MapRepresentable(
            region: $viewModel.region,
            selectedAnnotation: $viewModel.selectedFlight,
            annotations: viewModel.flightAnnotations,
            showsEarthAtNight: viewModel.showsEarthAtNight,
            nightLightsDate: nightLightsDate,
            viirsImageryDate: viirsImageryDate,
            auroraOverlay: viewModel.showsAurora ? aurora.overlay : nil,
            showsPowerGrid: viewModel.showsPowerGrid,
            selectPowerAsset: { selectedPowerAsset = $0 },
            gpsJamOverlay: viewModel.showsGPSJAM ? gpsJam.overlay : nil,
            selectGPSJAMCell: { gpsJam.selectedCell = $0 },
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
            viewModel.updateViewport(rect)
        }
        .edgesIgnoringSafeArea([.top,.bottom])
        .overlay(alignment: .top) {
            CountrySummaryView(viewModel: viewModel)
        }
        .overlay {
            countryListScrim
        }
        .overlay(alignment: .bottom) {
            MainMapControls(
                viewModel: viewModel,
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
        .task {
            await viewModel.loadCablesIfNeeded()
        }
        .task {
            // Hazards change slowly; refresh every 15 minutes while open.
            while !Task.isCancelled {
                await viewModel.updateHazards()
                try? await Task.sleep(for: .seconds(15 * 60))
            }
        }
        .task {
            await viewModel.retrieveCountries()
            guard !Task.isCancelled else { return }
            viewModel.startUpdatingFlightData()
        }
        .task(id: viewModel.current?.id) {
            await viewModel.refreshDestination()
        }
        .task(id: viewModel.travelSelection) {
            await viewModel.refreshPassportInformation()
        }
        .task(id: viewModel.selectedFlight?.id) {
            await viewModel.loadFlightDetails()
        }
        .onDisappear {
            viewModel.stopUpdatingFlightData()
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
        .sheet(item: Binding(get: { gpsJam.selectedCell }, set: { gpsJam.selectedCell = $0 })) { cell in
            GPSJAMCellDetails(cell: cell)
        }
        .sheet(item: $selectedPowerAsset) { asset in
            PowerAssetDetailsView(asset: asset)
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
