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
    }

    @ViewBuilder
    var statusViews: some View {
        if let name = viewModel.current?.name?.common, let flag = viewModel.current?.flags?.png {
            VStack {
                HStack(alignment: .center, spacing: 8) {
                    AsyncFlagView(flag: flag)
                    Text(name)
                }
                .shadow(color: .white, radius: 15)
                HStack {
                    if let status = viewModel.advisoryStatus {
                        CircularStatusView(colors: status.colors)
                            .frame(width: 20, height: 20, alignment: .center)
                        Text(status.data.eng.advisoryText)
                            .animation(.some(.easeIn), value: status)
                            .multilineTextAlignment(.center)
                    }
                }
                .shadow(color: .white, radius: 15)
                HStack {
                    if let status = viewModel.admissoryStatus {
                        CircularStatusView(colors: status.colors)
                            .frame(width: 20, height: 20, alignment: .center)
                        Text(status.category.capitalized)
                            .animation(.some(.easeIn), value: status)
                            .multilineTextAlignment(.center)
                    }
                }
                .shadow(color: .white, radius: 15)
            }
            .foregroundStyle(.white)
        }
    }
    
    @ViewBuilder
    var bottomStack: some View {
        VStack {
            HStack(spacing: 15) {
                LinearGradient(colors: [.tellusDark, .tellusLight], startPoint: .top, endPoint: .bottom)
                    .frame(width: 50, height: 50, alignment: .center)
                    .clipShape(.rect(cornerSize: .init(width: 50, height: 50)))
                    .shadow(color: .white, radius: 15)
                    .overlay {
                        Image(systemName: "globe.americas.fill")
                            .renderingMode(.template)
                            .foregroundColor(.white)
                            .symbolEffect(.variableColor, options: .nonRepeating, value: viewModel.current)
                    }.onTapGesture {
                        viewModel.selectRandomCountry()
                    }
                Spacer()
                LinearGradient(colors: [.tellusDark, .tellusLight], startPoint: .top, endPoint: .bottom)
                    .frame(width: 50, height: 50, alignment: .center)
                    .clipShape(.rect(cornerSize: .init(width: 50, height: 50)))
                    .shadow(color: .white, radius: 15)
                    .overlay {
                        AsyncFlagView(flag: viewModel.nationality?.flags?.png)
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
            .padding()
            selectionButton
        }
    }
    
    @ViewBuilder
    var selectionButton: some View {
        ExpandableSelectionButton(selectables: viewModel.countries, selected: $viewModel.current) { country in
            if let flag = country.flags?.png, let name = country.name?.common {
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
