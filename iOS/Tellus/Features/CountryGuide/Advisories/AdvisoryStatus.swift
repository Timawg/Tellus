//
//  AdvisoryStatus.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2023-09-20.
//

import Foundation
 
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
    // Null for some destinations (e.g. Puerto Rico).
    let openingText, closingText: String?

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

// MARK: - Advice sections

/// One topic from a section of the travel advice, such as Drugs or Driving in
/// "Laws and culture". `title` is nil for the general advice that comes before
/// the first topic.
struct AdviceSection: Identifiable, Equatable {
    enum Block: Equatable {
        case paragraph(AttributedString)
        case bullet(AttributedString, depth: Int)
        case subheading(String)
    }

    let id: Int
    let title: String?
    var blocks: [Block]
}

extension Array where Element == AdviceSection {
    /// The advice is written for Canadians. This drops what only applies to
    /// them: child abduction (about treaties with Canada), prisoner transfers
    /// to Canada, and the consular parts of dual citizenship, keeping whether
    /// the country recognises dual citizenship and its own rules for it.
    func withoutCanadaSpecificAdvice() -> [AdviceSection] {
        compactMap { section -> AdviceSection? in
            guard let title = section.title?.lowercased() else { return section }
            if title.contains("child abduction") || title.contains("canad") {
                return nil
            }
            if title.contains("transfer"), ["prison", "sentenced", "offender"].contains(where: title.contains) {
                return nil
            }
            guard title.contains("dual citizen") else { return section }
            var blocks = section.blocks.compactMap { $0.withoutCanadianServices() }
            // Drop subheadings left with nothing under them, like a "Useful
            // links" whose only link went to the Canadian government.
            blocks = blocks.enumerated().compactMap { index, block in
                let next = blocks.indices.contains(index + 1) ? blocks[index + 1] : nil
                return !block.isText && next?.isText != true ? nil : block
            }
            return blocks.contains(where: \.isText)
                ? AdviceSection(id: section.id, title: section.title, blocks: blocks)
                : nil
        }
        .enumerated()
        .map { AdviceSection(id: $0.offset, title: $0.element.title, blocks: $0.element.blocks) }
    }
}

extension AdviceSection.Block {

    var isText: Bool {
        if case .subheading = self { return false }
        return true
    }

    /// The block without sentences about Canadian consular help ("our ability to
    /// offer you consular services…"), or nil if nothing else is left. Blocks
    /// linking to the Canadian government are dropped whole.
    fileprivate func withoutCanadianServices() -> AdviceSection.Block? {
        let attributed: AttributedString
        let makeBlock: (AttributedString) -> AdviceSection.Block
        switch self {
        case .subheading:
            return self
        case .paragraph(let text):
            (attributed, makeBlock) = (text, AdviceSection.Block.paragraph)
        case .bullet(let text, let depth):
            (attributed, makeBlock) = (text, { .bullet($0, depth: depth) })
        }
        if attributed.runs.contains(where: { $0.link?.host?.hasSuffix("gc.ca") == true }) {
            return nil
        }

        let text = String(attributed.characters)
        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .bySentences) { sentence, _, _, _ in
            if let sentence { sentences.append(sentence.trimmingCharacters(in: .whitespaces)) }
        }
        let kept = sentences.filter { !Self.isAboutCanadianServices($0) }
        if kept.count == sentences.count { return self }
        if kept.isEmpty { return nil }
        // Rebuilt as plain text; these paragraphs don't carry links of their own.
        return makeBlock(AttributedString(kept.joined(separator: " ")))
    }

    private static func isAboutCanadianServices(_ sentence: String) -> Bool {
        let words = sentence.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
        return words.contains("consular") || !Set(words).isDisjoint(with: ["we", "us", "our"])
    }
}

extension Information {
    /// Advice page on travel.gc.ca, which the API data comes from.
    var travelAdviceURL: URL? {
        URL(string: "https://travel.gc.ca/destinations/\(urlSlug)")
    }
}
