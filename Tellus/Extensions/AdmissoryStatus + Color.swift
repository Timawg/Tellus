//
//  AdmissoryStatus + Color.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2024-07-23.
//

import Foundation
import SwiftUI

extension AdmissoryStatus {
    
    var colors: [Color] {
        switch AdmissoryStatus.Status(value: self.category) {
        case .visaFree: return .secure
        case .visaOnArrival, .electronicVisa: return .semisecure
        case .visaRequired: return .caution
        case .covidBan, .noAdmission: return .danger
        default: return []
        }
    }
}
