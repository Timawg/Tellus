//
//  ExchangeRates.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2026-11-04.
//

import Foundation

/// Daily rates from one currency to every other, from currency-api. The
/// response is `{"date": "2026-11-04", "sek": {"eur": 0.091, …}}`, keyed by
/// the lowercase base code, so it's decoded by hand.
struct ExchangeRates: Decodable {
    let base: String
    let date: String
    /// Units of each currency per one unit of `base`, keyed by uppercase code.
    let rates: [String: Double]

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        date = try container.decode(String.self, forKey: AnyKey(stringValue: "date"))
        guard let baseKey = container.allKeys.first(where: { $0.stringValue != "date" }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "No rates in response"))
        }
        base = baseKey.stringValue.uppercased()
        let raw = try container.decode([String: Double].self, forKey: baseKey)
        rates = Dictionary(uniqueKeysWithValues: raw.map { ($0.key.uppercased(), $0.value) })
    }
}

/// How much of a destination's currency one unit of the home currency buys.
struct ExchangeRate: Equatable, Identifiable {
    let home: String
    let destination: String
    let rate: Double
    let date: String

    var id: String { destination }

    /// One unit of the destination currency in the home currency.
    var inverse: Double { 1 / rate }

    /// "16.63", "0.06011", "1,534": four significant digits reads well for
    /// both tiny and large rates.
    static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.significantDigits(1...4)))
    }
}
