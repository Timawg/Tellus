//
//  AdvisoryStatus + Color.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2024-07-23.
//

import Foundation
import SwiftUI

extension AdvisoryStatus {
    
    var colors: [Color] {
        switch DataClass.State(value: self.data.advisoryState){
        case .secure: return .secure
        case .caution: return .semisecure
        case .avoid: return .caution
        case .danger: return .danger
        default: return []
        }
    }
}
