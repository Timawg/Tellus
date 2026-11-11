//
//  PassportStatus.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2023-09-19.
//

import Foundation

struct AdmissoryStatus: Codable, Equatable {
    
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
            let eVisaStrings = ["eta", "evisa", "e-visa", "visa on arrival / evisa"]
            
            if eVisaStrings.contains(value.lowercased()) {
                self = .electronicVisa
            } else {
                self.init(rawValue: value)
            }
        }
    }
    static func == (lhs: AdmissoryStatus, rhs: AdmissoryStatus) -> Bool {
        rhs.passport == lhs.passport && rhs.destination == lhs.destination && lhs.status == rhs.status
    }
    
    let passport, destination, dur, status: String
    let category, lastUpdated: String
    let error: AdmissoryError

    enum CodingKeys: String, CodingKey {
        case passport, destination, dur, status, category
        case lastUpdated = "last_updated"
        case error
    }
}

// MARK: - Error
struct AdmissoryError: Codable {
    let status: Bool
    let error: String
}

// MARK: - Passport Index dataset
extension AdmissoryStatus {

    /// Builds a status from a raw Passport Index requirement value, e.g. "90",
    /// "visa required", "visa on arrival", "e-visa" or "no admission".
    init(passport: String, destination: String, requirement: String) {
        let category = AdmissoryStatus.normalizeCategory(requirement)
        let trimmed = requirement.trimmingCharacters(in: .whitespacesAndNewlines)
        // A numeric requirement is the number of visa-free days allowed.
        let duration = Int(trimmed) != nil ? trimmed : ""
        self.init(
            passport: passport,
            destination: destination,
            dur: duration,
            status: category,
            category: category,
            lastUpdated: "",
            error: AdmissoryError(status: false, error: "")
        )
    }

    /// Maps a raw Passport Index requirement to a category the app understands.
    private static func normalizeCategory(_ requirement: String) -> String {
        let value = requirement.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        // Numbers (and "-1" for one's own country) mean visa-free entry.
        if Int(value) != nil {
            return Status.visaFree.rawValue
        }
        switch value {
        case "visa free", "-1": return Status.visaFree.rawValue
        case "visa on arrival": return Status.visaOnArrival.rawValue
        case "e-visa", "eta": return "e-visa"
        case "visa required": return Status.visaRequired.rawValue
        case "no admission": return Status.noAdmission.rawValue
        default: return value
        }
    }
}
