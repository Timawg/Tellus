//
//  Array + Color.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2024-07-23.
//

import Foundation
import SwiftUI

extension Array where Element == Color {
    
    static var secure: [Color] {
        return [.tellusLight, .green, .gray]
    }
    
    static var semisecure: [Color] {
        return [.tellusDark, .blue, .gray]
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

extension Color {
    
    static var tellusDark: Color {
        Color(.tellusDark)
    }
    
    static var tellusLight: Color {
        Color(.tellusLight)
    }
}

