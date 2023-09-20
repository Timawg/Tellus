//
//  ContentView.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2023-09-14.
//

import SwiftUI
import MapKit

struct ContentView: View {
    
    @State var region: MKCoordinateRegion = .init(.world)
    @State var countries: [Country] = []
    @State var current: Country!
    @State var nationality: Country? = getPersistedNationality()
    @State var passportStatus: PassportStatus?
    @State var passportStatusColors: [Color] = []
    @State var advisoryStatus: AdvisoryStatus?
    @State var advisoryStatusColors: [Color] = []

    var body: some View {
        Map(coordinateRegion:$region)
            .edgesIgnoringSafeArea([.top,.bottom])
            .overlay(alignment: .top) {
                if let name = current?.name?.common, let flag = current?.flags?.png {
                    VStack {
                        HStack(alignment: .center, spacing: 8) {
                            AsyncFlagView(flag: flag)
                            Text(name)
                        }
                        HStack {
                            CircularStatusView(colors: $advisoryStatusColors)
                                .frame(width: 20, height: 20, alignment: .center)
                            Text(advisoryStatus?.data.eng.advisoryText ?? "").animation(.some(.easeIn), value: advisoryStatus)
                                .multilineTextAlignment(.center)
                        }
                        HStack {
                            CircularStatusView(colors: $passportStatusColors)
                                .frame(width: 20, height: 20, alignment: .center)
                            Text(passportStatus?.category.capitalized ?? "").animation(.some(.easeIn), value: passportStatus)
                        }
                    }
                }
            }
            .overlay(alignment: .bottom) {
                HStack(spacing: 45) {
                    RoundedRectangle(cornerSize: .init(width: 200, height: 50))
                        .foregroundColor(.cyan)
                        .frame(width: 50, height: 50, alignment: .center)
                        .overlay {
                            RoundedRectangle(cornerSize: .init(width: 200, height: 50))
                                .foregroundColor(.cyan)
                                .frame(width: 50, height: 50, alignment: .center).overlay {
                                    Image(systemName: "questionmark.diamond")
                                        .renderingMode(.template)
                                        .foregroundColor(.white)
                                }
                        }.onTapGesture {
                            current = countries.randomElement()
                        }
                    RoundedRectangle(cornerSize: .init(width: 100, height: 50))
                        .foregroundColor(.cyan)
                        .frame(width: 100, height: 50, alignment: .center)
                        .overlay {
                            HStack {
                                AsyncFlagView(flag: current?.flags?.png)
                                    .padding(.leading)
                                Picker("Select Country", selection: $current) {
                                    Text(current?.name?.common ?? "").hidden().tag(current)
                                    ForEach(countries, id: \.self) { country in
                                        HStack(alignment: .center, spacing: 8) {
                                            if let flag = country.flags?.png, let name = country.name?.common {
                                                AsyncFlagView(flag: flag)
                                                Text(name)
                                            }
                                        }.tag(Optional(country))
                                    }
                                }
                            }.tint(.white)
                        }
                    RoundedRectangle(cornerSize: .init(width: 200, height: 50))
                        .foregroundColor(.cyan)
                        .frame(width: 50, height: 50, alignment: .center)
                        .overlay {
                            AsyncFlagView(flag: nationality?.flags?.png)
                            Image("passport-icon").resizable()
                                .frame(maxWidth: 25, maxHeight: 30, alignment: .center)
                            Picker("Select Country", selection: $nationality) {
                                Text(nationality?.name?.common ?? "").hidden().tag(nationality)
                                ForEach(countries, id: \.self) { country in
                                    HStack(alignment: .center, spacing: 8) {
                                        if let flag = country.flags?.png, let name = country.name?.common {
                                            AsyncFlagView(flag: flag)
                                            Text(name)
                                        }
                                    }.tag(Optional(country))
                                }
                            }.tint(.clear)
                        }.onTapGesture {
                            updateRegion()
                        }
                }
            }.task {
                countries = await retrieveCountries().sorted { $0.name?.common ?? "" < $1.name?.common ?? "" }
                current = countries.randomElement()
            }.onChange(of: current) { newValue in
                Task {
                    await updateAdvisoryStatus()
                    await updatePassportStatus()
                }
                updateRegion()
            }.onChange(of: nationality) { newValue in
                persist(nationality: newValue)
                Task {
                    await updatePassportStatus()
                }
            }
    }
    
    func persist(nationality: Country?) {
        if let nationality, let encoded = try? JSONEncoder().encode(nationality) {
            UserDefaults.standard.set(encoded, forKey: "nationality")
        }
    }
    
    static func getPersistedNationality() -> Country? {
        guard let data = UserDefaults.standard.object(forKey: "nationality") as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(Country.self, from: data)
    }
    
    func updatePassportStatus() async {
        passportStatus = await retrievePassportStatus()
        passportStatusColors = {
            switch PassportStatus.Status(value: passportStatus?.category) {
            case .visaFree: return .secure
            case .visaOnArrival, .electronicVisa: return .semisecure
            case .visaRequired: return .caution
            case .covidBan, .noAdmission: return .danger
            default: return []
            }
        }()
    }
    
    func updateAdvisoryStatus() async {
        advisoryStatus = await retrieveAdvisoryStatus()
        advisoryStatusColors = {
            switch DataClass.State(value: advisoryStatus?.data.advisoryState){
            case .secure: return .secure
            case .caution: return .semisecure
            case .avoid: return .caution
            case .danger: return .danger
            default: return []
            }
        }()
    }
    
    func updateRegion() {
        guard let country = current else { return }

        if let area = country.area {
            let centerLatitude: CLLocationDegrees = country.latlng[0]
            let centerLongitude: CLLocationDegrees = country.latlng[1]
            withAnimation {
                self.region = calculateRegion(area: area, latitude: centerLatitude, longitude: centerLongitude)
            }
        } else {
            guard let name = country.name?.common else {
                return
            }
            Task {
                guard let region = await findRegion(by: name) else {
                    return
                }
                withAnimation {
                    self.region = region
                }
            }
        }
    }
    
    func calculateRegion(area: Double, latitude: CLLocationDegrees, longitude: CLLocationDegrees) -> MKCoordinateRegion {
        
        // Calculate deltas
        let latitudeDelta = sqrt(area) / 110
        let longitudeDelta = (sqrt(area) / 110) + latitudeDelta

        // Calculate the span
        let span = MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)

        // Create the coordinate region
        let centerCoordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return MKCoordinateRegion(center: centerCoordinate, span: span)
    }

    func findRegion(by name: String) async -> MKCoordinateRegion? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = name
        let results = try? await MKLocalSearch(request: request).start()
        return results?.boundingRegion
    }
    
    func retrieveCountries() async -> [Country] {
        guard let url = URL(string: "https://restcountries.com/v3.1/all") else {
            return []
        }
        let data = try! await URLSession.shared.data(from: url).0
        
        let countries = try! JSONDecoder().decode([Country].self, from: data)
        return countries
    }
    
    func retrievePassportStatus() async -> PassportStatus? {
        guard let passport = nationality?.cca2,
              let destination = current.cca2 else {
            return nil
        }
        
        let urlString = "https://rough-sun-2523.fly.dev/api/\(passport)/\(destination)"
        guard let url = URL(string: urlString) else {
            return nil
        }
        let data = try! await URLSession.shared.data(from: url).0
        
        let status = try? JSONDecoder().decode(PassportStatus.self, from: data)
        return status
    }
    
    func retrieveAdvisoryStatus() async -> AdvisoryStatus? {
        guard let destination = current.cca2 else {
            return nil
        }
        
        let urlString = "https://data.international.gc.ca/travel-voyage/cta-cap-\(destination).json"
        guard let url = URL(string: urlString) else {
            return nil
        }
        let data = try! await URLSession.shared.data(from: url).0
        
        let status = try? JSONDecoder().decode(AdvisoryStatus.self, from: data)
        return status
    }
}

struct AsyncFlagView: View {
    
    let flag: String?
    
    var body: some View {
        if let flag {
            AsyncImage(
                url: .init(string: flag),
                content: { image in
                    image.resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 40, maxHeight: 25)
                },
                placeholder: {
                    EmptyView()
                }
            )
        } else {
            ProgressView()
        }
    }
}

struct CircularStatusView: View {
    
    @Binding var colors: [Color]
    
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: colors),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                ).shadow(radius: 4)
        }
    }
}

extension Array where Element == Color {
    
    static var secure: [Color] {
        return [.mint, .green, .gray]
    }

    static var semisecure: [Color] {
        return [.green, .blue, .gray]
    }

    static var caution: [Color] {
        return [.yellow, .orange, .gray]
    }

    static var avoid: [Color] {
        return [.orange, .red.opacity(0.8), .gray]
    }

    static var danger: [Color] {
        return [.red.opacity(0.8), .red, .black.opacity(0.8)]
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        CircularStatusView(colors: .constant(.secure))
    }
}
