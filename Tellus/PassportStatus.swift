//
//  PassportStatus.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2023-09-19.
//

import Foundation

struct PassportStatus: Codable, Equatable {
    
    enum Status: String {
        case visaFree = "visa-free"
        case electronicVisa = "eta"
        case visaOnArrival = "visa on arrival"
        case visaRequired = "visa required"
        case covidBan = "covid ban"
        case noAdmission = "not admitted"
        
        init?(value: String?) {
            guard let value else {
                return nil
            }
            let eVisaStrings = ["eta", "evisa", "visa on arrival / evisa"]
            
            if eVisaStrings.contains(value.lowercased()) {
                self = .electronicVisa
            } else {
                self.init(rawValue: value)
            }
        }
    }
    static func == (lhs: PassportStatus, rhs: PassportStatus) -> Bool {
        rhs.passport == lhs.passport && rhs.destination == lhs.destination && lhs.status == rhs.status
    }
    
    let passport, destination, dur, status: String
    let category, lastUpdated: String
    let error: Error

    enum CodingKeys: String, CodingKey {
        case passport, destination, dur, status, category
        case lastUpdated = "last_updated"
        case error
    }
}

// MARK: - Error
struct Error: Codable {
    let status: Bool
    let error: String
}
