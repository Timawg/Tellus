//
//  TellusApp.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2023-09-14.
//

import SwiftUI

@main
struct TellusApp: App {

    @State private var mainMapViewModel = MainMapViewModel(
        services: MainMapServices(networkService: NetworkService()),
        preferences: UserDefaultsMapPreferencesStore(defaults: .standard)
    )

    var body: some Scene {
        WindowGroup {
            MainMapView(viewModel: mainMapViewModel)
        }
    }
}
