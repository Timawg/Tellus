//
//  OutbreakNews.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2026-11-04.
//

import Foundation

/// A WHO Disease Outbreak News report.
struct OutbreakReport: Equatable, Identifiable {
    let id: String
    let disease: String
    /// The places part of the title, e.g. "Democratic Republic of the Congo,
    /// Kenya and Nigeria".
    let places: String
    let published: Date
    /// The first couple of sentences of WHO's summary.
    let summary: String
    let url: URL?
}

/// WHO's OData feed: `{"value": [{"Title": …, "PublicationDate": …}]}`.
struct WHOOutbreakList: Decodable {

    struct Item: Decodable {
        let Title: String
        let PublicationDate: String
        let UrlName: String?
        let Summary: String?
    }

    let value: [Item]

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    var reports: [OutbreakReport] {
        value.compactMap { item in
            guard let published = Self.dateFormatter.date(from: item.PublicationDate) else { return nil }
            let (disease, places) = Self.split(title: item.Title)
            return OutbreakReport(
                id: item.UrlName ?? item.Title + item.PublicationDate,
                disease: disease,
                places: places,
                published: published,
                summary: Self.shortSummary(item.Summary ?? ""),
                url: item.UrlName.flatMap { URL(string: "https://www.who.int/emergencies/disease-outbreak-news/item/\($0)") }
            )
        }
    }

    /// Titles read "Nipah virus disease - India", "Avian Influenza A(H5N1)-
    /// Cambodia", "Marburg virus disease– United Republic of Tanzania" or
    /// "Ebola disease caused by Bundibugyo virus, Democratic Republic of the
    /// Congo & Uganda". The separator is the last en or em dash, or a hyphen
    /// followed by a space or after a bracket ("A(H5N2)-Mexico"), so names
    /// like "Guinea-Bissau" stay whole.
    static func split(title: String) -> (disease: String, places: String) {
        if let range = title.range(of: #"\s*(?:[–—]|-(?=\s)|(?<=\))-)\s*(?=[^–—]*$)"#, options: .regularExpression),
           range.lowerBound > title.startIndex, range.upperBound < title.endIndex {
            return (String(title[..<range.lowerBound]), String(title[range.upperBound...]))
        }
        if let comma = title.firstIndex(of: ",") {
            return (String(title[..<comma]), String(title[title.index(after: comma)...]).trimmingCharacters(in: .whitespaces))
        }
        return (title, "")
    }

    /// Up to two sentences, at most about 300 characters.
    static func shortSummary(_ text: String) -> String {
        let plain = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        var sentences: [String] = []
        plain.enumerateSubstrings(in: plain.startIndex..<plain.endIndex, options: .bySentences) { sentence, _, _, stop in
            if let sentence { sentences.append(sentence.trimmingCharacters(in: .whitespaces)) }
            if sentences.count == 2 { stop = true }
        }
        let summary = sentences.joined(separator: " ")
        return summary.count > 300 ? String(summary.prefix(297)) + "…" : summary
    }
}

/// Finds which countries each report is about.
enum OutbreakCountryMatcher {

    /// Reports per country (ISO alpha-2), keeping only the newest report per
    /// disease, newest first. Each report's places are matched once against
    /// every country's names, longest first, so "Congo" isn't found inside
    /// "Democratic Republic of the Congo" and "Guinea" isn't found inside
    /// "Guinea-Bissau".
    static func index(_ reports: [OutbreakReport], countries: [Country]) -> [String: [OutbreakReport]] {
        let names = countries.flatMap { country in
            candidateNames(for: country).map { (name: $0.lowercased(), code: country.cca2 ?? "") }
        }
        .filter { !$0.code.isEmpty }
        .sorted { $0.name.count > $1.name.count }

        var index: [String: [OutbreakReport]] = [:]
        var seen: [String: Set<String>] = [:]
        for report in reports.sorted(by: { $0.published > $1.published }) {
            for code in matchedCodes(in: report.places, names: names)
            where seen[code, default: []].insert(diseaseKey(report.disease)).inserted {
                index[code, default: []].append(report)
            }
        }
        return index
    }

    /// Names WHO uses that the country dataset doesn't list.
    private static let whoNames = [
        "VN": ["Viet Nam"],
        "TR": ["Türkiye", "Turkey"],
        "CI": ["Côte d’Ivoire", "Côte d'Ivoire", "Cote d'Ivoire"],
        "CZ": ["Czechia"],
        "KP": ["Democratic People's Republic of Korea"],
        "LA": ["Lao People's Democratic Republic"],
        "SY": ["Syrian Arab Republic"],
        "MD": ["Republic of Moldova"],
    ]

    static func candidateNames(for country: Country) -> [String] {
        var names = [country.name?.common, country.name?.official].compactMap { $0 }
        names += country.cca2.flatMap { whoNames[$0] } ?? []
        names += (country.altSpellings ?? []).filter { $0.count > 3 && $0 != $0.uppercased() }
        return names
    }

    /// Plain substring search with word boundaries checked by hand; much
    /// faster than a regular expression per name.
    private static func matchedCodes(in places: String, names: [(name: String, code: String)]) -> Set<String> {
        var text = Array(places.lowercased())
        var codes = Set<String>()
        for (name, code) in names {
            let needle = Array(name)
            guard needle.count <= text.count else { continue }
            var index = 0
            while index + needle.count <= text.count {
                if text[index] == needle[0], Array(text[index..<index + needle.count]) == needle,
                   index == 0 || !text[index - 1].isLetter,
                   index + needle.count == text.count || !text[index + needle.count].isLetter {
                    codes.insert(code)
                    // Blank it out so shorter names can't match inside it.
                    for offset in index..<index + needle.count { text[offset] = "#" }
                    index += needle.count
                } else {
                    index += 1
                }
            }
        }
        return codes
    }

    /// Same outbreak reported several times ("Ebola disease caused by
    /// Bundibugyo virus").
    private static func diseaseKey(_ disease: String) -> String {
        disease.lowercased().trimmingCharacters(in: .whitespaces)
    }
}
