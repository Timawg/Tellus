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
    let capitalInfo: CapitalInfo?

    /// Flag image URL. The country dataset only provides an emoji flag, so the
    /// displayable PNG is derived from the ISO 3166-1 alpha-2 code via flagcdn.
    /// Falls back to the API-provided `flags.png` when present.
    var flagURL: String? {
        if let png = flags?.png {
            return png
        }
        guard let cca2 else { return nil }
        return "https://flagcdn.com/w320/\(cca2.lowercased()).png"
    }

    /// "Swedish krona (kr)", one per currency.
    var currencyDescriptions: [String] {
        (currencies ?? [:]).sorted { $0.key < $1.key }.map { code, currency in
            let name = currency.name ?? code
            if let symbol = currency.symbol, symbol != code {
                return "\(name) (\(symbol))"
            }
            return "\(name) (\(code))"
        }
    }

    var languageNames: [String] {
        (languages ?? [:]).values.sorted()
    }

    /// International dialling code, e.g. "+46". Countries sharing a root with
    /// many suffixes (like +1 for North America) show just the root.
    var callingCode: String? {
        guard let root = idd?.root, !root.isEmpty else { return nil }
        guard let suffixes = idd?.suffixes, suffixes.count == 1 else { return root }
        return root + suffixes[0]
    }
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
/// Keyed by ISO 4217 code, e.g. "SEK".
typealias Currencies = [String: CurrencyInfo]

struct CurrencyInfo: Codable {
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
/// Language names keyed by ISO 639-3 code, e.g. "swe": "Swedish".
typealias Languages = [String: String]
 
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
