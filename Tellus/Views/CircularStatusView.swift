//
//  CircularStatusView.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2024-07-23.
//

import Foundation
import SwiftUI

struct CircularStatusView: View {
    
    var colors: [Color]
    
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
