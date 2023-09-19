//
//  Country.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2023-09-14.
//

import Foundation

struct Country: Codable, Hashable, Identifiable {
    let id = UUID()
    
    static func == (lhs: Country, rhs: Country) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    let name: Name?
    let tld: [String]?
    let cca2, ccn3, cca3, cioc: String?
    let independent: Bool?
    let status: String?
    let unMember: Bool?
    let currencies: Currencies?
    let idd: Idd?
    let capital, altSpellings: [String]?
    let region, subregion: String?
    let languages: Languages?
    let translations: [String: Translation]
    let latlng: [Double]
    let landlocked: Bool?
    let borders: [String]?
    let area: Double?
    let demonyms: Demonyms?
    let flag: String?
    let maps: Maps?
    let population: Int?
    let fifa: String?
    let car: Car?
    let timezones, continents: [String]?
    let flags, coatOfArms: CoatOfArms?
    let startOfWeek: String?
    let capitalInfo: CapitalInfo
}
 
// MARK: - CapitalInfo
struct CapitalInfo: Codable {
    let latlng: [Double]?
}
 
// MARK: - Car
struct Car: Codable {
    let signs: [String]?
    let side: String?
}
 
// MARK: - CoatOfArms
struct CoatOfArms: Codable {
    let png: String?
    let svg: String?
}
 
// MARK: - Currencies
struct Currencies: Codable {
    let egp, ils, jod: EGP?
 
    enum CodingKeys: String, CodingKey {
        case egp = "EGP"
        case ils = "ILS"
        case jod = "JOD"
    }
}
 
// MARK: - EGP
struct EGP: Codable {
    let name, symbol: String?
}
 
// MARK: - Demonyms
struct Demonyms: Codable {
    let eng, fra: Eng?
}
 
// MARK: - Eng
struct Eng: Codable {
    let f, m: String?
}
 
// MARK: - Idd
struct Idd: Codable {
    let root: String?
    let suffixes: [String]?
}
 
// MARK: - Languages
struct Languages: Codable {
    let ara: String?
}
 
// MARK: - Maps
struct Maps: Codable {
    let googleMaps, openStreetMaps: String?
}
 
// MARK: - Name
struct Name: Codable {
    let common, official: String?
}
 
// MARK: - Translation
struct Translation: Codable {
    let official, common: String?
}
