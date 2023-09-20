//
//  AdvisoryStatus.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2023-09-20.
//

import Foundation
 
// MARK: - Welcome
struct AdvisoryStatus: Codable, Equatable {
    static func == (lhs: AdvisoryStatus, rhs: AdvisoryStatus) -> Bool {
        lhs.data == rhs.data
    }
    
    let metadata: Metadata
    let data: DataClass
}
 
// MARK: - DataClass
struct DataClass: Codable, Equatable {
    static func == (lhs: DataClass, rhs: DataClass) -> Bool {
        lhs.countryISO == rhs.countryISO
    }
    
    let countryISO: String
    let advisoryState, hasAdvisoryWarning, hasRegionalAdvisory, hasContent: Int
    let updateMetadata: String
    let eng, fra: Information
    
    enum State: Int {
        case secure
        case caution
        case avoid
        case danger
        
        init?(value: Int?) {
            guard let value else { return nil }
            self.init(rawValue: value)
        }
    }
 
    enum CodingKeys: String, CodingKey {
        case countryISO = "country-iso"
        case advisoryState = "advisory-state"
        case hasAdvisoryWarning = "has-advisory-warning"
        case hasRegionalAdvisory = "has-regional-advisory"
        case hasContent = "has-content"
        case updateMetadata = "update-metadata"
        case eng, fra
    }
}
 
// MARK: - Eng
struct Information: Codable {
    let name, urlSlug, geoGroup, friendlyDate: String
    let advisoryText, recentUpdates, advisories, security: String
    let entryExit, health, lawsCulture, disastersClimate: String
    let officesHelpAbroad: OfficesHelpAbroad
    let officesHTML: String
    let offices: [Office]
 
    enum CodingKeys: String, CodingKey {
        case name
        case urlSlug = "url-slug"
        case geoGroup = "geo-group"
        case friendlyDate = "friendly-date"
        case advisoryText = "advisory-text"
        case recentUpdates = "recent-updates"
        case advisories, security
        case entryExit = "entry-exit"
        case health
        case lawsCulture = "laws-culture"
        case disastersClimate = "disasters-climate"
        case officesHelpAbroad = "offices-help-abroad"
        case officesHTML = "offices-html"
        case offices
    }
}
 
// MARK: - Office
struct Office: Codable {
    let country, city, countryISO, lat: String?
    let lng: String?
    let honoraryConsul, hasPassportServices: Int?
    let type, address, postalAddress, telLegacy: String?
    let emergencyTollFreeLegacy, faxLegacy, email1, email2: String?
    let email3: String?
    let internet: String?
    let note1Title, note1Text, note2Title, note2Text: String?
    let note3Title, note3Text: String?
    let facebook: String?
    let facebookLabel: String?
    let twitter: String?
    let twitterLabel, consularDistrict: String?
 
    enum CodingKeys: String, CodingKey {
        case country, city
        case countryISO = "country-iso"
        case lat, lng
        case honoraryConsul = "honorary-consul"
        case hasPassportServices = "has-passport-services"
        case type, address
        case postalAddress = "postal-address"
        case telLegacy = "tel-legacy"
        case emergencyTollFreeLegacy = "emergency-toll-free-legacy"
        case faxLegacy = "fax-legacy"
        case email1 = "email-1"
        case email2 = "email-2"
        case email3 = "email-3"
        case internet
        case note1Title = "note-1-title"
        case note1Text = "note-1-text"
        case note2Title = "note-2-title"
        case note2Text = "note-2-text"
        case note3Title = "note-3-title"
        case note3Text = "note-3-text"
        case facebook
        case facebookLabel = "facebook-label"
        case twitter
        case twitterLabel = "twitter-label"
        case consularDistrict = "consular-district"
    }
}
 
// MARK: - OfficesHelpAbroad
struct OfficesHelpAbroad: Codable {
    let openingText, closingText: String
 
    enum CodingKeys: String, CodingKey {
        case openingText = "opening-text"
        case closingText = "closing-text"
    }
}
 
// MARK: - Metadata
struct Metadata: Codable {
    let generated: Generated
}
 
// MARK: - Generated
struct Generated: Codable {
    let timestamp: Int
    let date: String
}
