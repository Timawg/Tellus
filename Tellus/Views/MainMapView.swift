//
//  ContentView.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2023-09-14.
//

import SwiftUI
import MapKit
import Observation

struct MainMapView: View {
    
    @Bindable var viewModel: MainMapViewModel
    
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
                        Text(status.data.eng.advisoryText).animation(.some(.easeIn), value: status)
                            .multilineTextAlignment(.center)
                    }
                    
                }
                .shadow(color: .white, radius: 15)
                HStack {
                    if let status = viewModel.admissoryStatus {
                        CircularStatusView(colors: status.colors)
                            .frame(width: 20, height: 20, alignment: .center)
                        Text(status.category.capitalized).animation(.some(.easeIn), value: status)
                            .multilineTextAlignment(.center)
                    }
                }
                .shadow(color: .white, radius: 15)
            }
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
    
    var body: some View {
        ClusteredMap(region: $viewModel.region, annotations: viewModel.flightAnnotations)
            .edgesIgnoringSafeArea([.top,.bottom])
            .overlay(alignment: .top) {
                statusViews
            }
            .overlay(alignment: .bottom) {
                HStack(spacing: 15) {
                    RoundedRectangle(cornerSize: .init(width: 200, height: 50))
                        .frame(width: 50, height: 50, alignment: .center)
                        .shadow(color: .white, radius: 15)
                        .overlay {
                            RoundedRectangle(cornerSize: .init(width: 200, height: 50))
                                .foregroundColor(.clear)
                                .background(content: {
                                    LinearGradient(colors: [.tellusDark, .tellusLight], startPoint: .top, endPoint: .bottom).cornerRadius(50)
                                })
                                .frame(width: 50, height: 50, alignment: .center)
                                .overlay {
                                    Image(systemName: "globe.americas.fill")
                                        .renderingMode(.template)
                                        .foregroundColor(.white)
                                        .symbolEffect(.variableColor, options: .nonRepeating, value: viewModel.current)
                                }
                        }.onTapGesture {
                            viewModel.selectRandomCountry()
                        }
                    
                    selectionButton

                    RoundedRectangle(cornerSize: .init(width: 200, height: 50))
                        .foregroundColor(.clear)
                        .background(content: {
                            LinearGradient(colors: [.tellusDark, .tellusLight], startPoint: .top, endPoint: .bottom)
                                .cornerRadius(50)
                        })
                        .frame(width: 50, height: 50, alignment: .center)
                        .shadow(color: .white, radius: 15)
                        .overlay {
                            AsyncFlagView(flag: viewModel.nationality?.flags?.png)
                            Image("passport-icon").resizable()
                                .frame(maxWidth: 25, maxHeight: 30, alignment: .center)
                            Picker("Select Country", selection: $viewModel.nationality) {
                                Text(viewModel.nationality?.name?.common ?? "").hidden().tag(viewModel.nationality)
                                ForEach(viewModel.countries, id: \.self) { country in
                                    HStack(alignment: .center, spacing: 8) {
                                        if let flag = country.flags?.png, let name = country.name?.common {
                                            AsyncFlagView(flag: flag)
                                            Text(name)
                                        }
                                    }.tag(Optional(country))
                                }
                            }
                        }.onTapGesture {
                            viewModel.updateRegion()
                        }
                }
                
            }.task {
                await viewModel.retrieveCountries()
                await viewModel.updateFlightData()
            }.onChange(of: viewModel.current) { newValue in
                Task {
                    await viewModel.updateAdvisoryStatus()
                }
                Task {
                    await viewModel.updateAdmissoryStatus()
                }
                viewModel.updateRegion()
            }.onChange(of: viewModel.nationality) { newValue in
                viewModel.persist(nationality: newValue)
                Task {
                    await viewModel.updateAdmissoryStatus()
                }
            }
    }
    
}

struct ClusteredMap: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    var annotations: [MKAnnotation]

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: ClusteredMap

        init(parent: ClusteredMap) {
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            parent.region = mapView.region
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKClusterAnnotation {
                let identifier = "Flight"
                var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                if view == nil {
                    view = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                    
                    view?.image = UIImage(systemName: "airplane")?.withRenderingMode(.alwaysTemplate)
                }
                view?.tintColor = .blue
                view?.transform = .init(rotationAngle: -1.5707963267948966)
                
                if let annotation = annotation as? FlightAnnotation, let degrees = annotation.track {
                    view?.transform = .init(rotationAngle: -1.5707963267948966)
                    UIView.animate(withDuration: 0.2) {
                        view?.transform = .init(rotationAngle:CGFloat(degrees) * .pi / 180.0)
                    }
                }
                view?.annotation = annotation
                return view
            }

            let identifier = "Flight"
            var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
            if view == nil {
                view = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)

            }
            view?.image = UIImage(systemName: "airplane")?.withRenderingMode(.alwaysTemplate)
            view?.tintColor = .blue
            view?.transform = .init(rotationAngle: -1.5707963267948966)
            if let annotation = annotation as? FlightAnnotation, let degrees = annotation.track {
                view?.transform = .init(rotationAngle: -1.5707963267948966)
                UIView.animate(withDuration: 0.2) {
                    view?.transform = .init(rotationAngle:CGFloat(degrees) * .pi / 180.0)
                }
            }
            view?.annotation = annotation
            return view
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.register(MKAnnotationView.self, forAnnotationViewWithReuseIdentifier: "Flight")
        mapView.addAnnotations(annotations)
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.showsTraffic = true
        mapView.showsUserLocation = true
        mapView.isZoomEnabled = true
        mapView.isScrollEnabled = true
        mapView.isRotateEnabled = true
        mapView.isPitchEnabled = true
        mapView.setRegion(region, animated: false)
        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        uiView.removeAnnotations(uiView.annotations)
        uiView.addAnnotations(annotations)
        uiView.setRegion(region, animated: true)
    }
}


