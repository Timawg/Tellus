//
//  DestinationGuide.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2026-11-04.
//

import Foundation

/// The parts of a destination's travel advice shown in the destination guide,
/// parsed once from the advisory's HTML so the sheet can switch between them
/// instantly.
struct DestinationGuide {

    enum Topic: String, CaseIterable, Identifiable {
        case overview, entry, health, laws, climate

        var id: Self { self }

        var title: String {
            switch self {
            case .overview: "Overview"
            case .entry: "Entry"
            case .health: "Health"
            case .laws: "Laws"
            case .climate: "Climate"
            }
        }

        /// Heading for the topic's advice list.
        var heading: String {
            switch self {
            case .overview: "Overview"
            case .entry: "Entry requirements"
            case .health: "Health"
            case .laws: "Laws & culture"
            case .climate: "Natural disasters & climate"
            }
        }
    }

    let advisories: [AdviceSection]
    let entry: [AdviceSection]
    let health: [AdviceSection]
    let laws: [AdviceSection]
    let climate: [AdviceSection]
    /// The "Local services" advice: emergency numbers and tourist helplines,
    /// with the numbers made tappable.
    let emergency: [AdviceSection.Block]
    let updated: String
    let adviceURL: URL?

    init(information: Information) {
        advisories = AdviceSection.sections(fromHTML: information.advisories)
        entry = AdviceSection.sections(fromHTML: information.entryExit)
            .withoutCanadaSpecificAdvice()
            .withoutCanadianEntryRules()
            .withoutStubs()
        health = AdviceSection.sections(fromHTML: information.health)
            .withoutCanadaSpecificAdvice()
            .withoutStubs()
        laws = AdviceSection.sections(fromHTML: information.lawsCulture)
            .withoutCanadaSpecificAdvice()
        climate = AdviceSection.sections(fromHTML: information.disastersClimate)
            .withoutStubs()
        emergency = Self.emergencyBlocks(fromOfficesHTML: information.officesHTML)
        updated = information.friendlyDate
        adviceURL = information.travelAdviceURL
    }

    func sections(for topic: Topic) -> [AdviceSection] {
        switch topic {
        case .overview: []
        case .entry: entry
        case .health: health
        case .laws: laws
        case .climate: climate
        }
    }

    // MARK: Emergency numbers

    /// The offices HTML starts with "Local services" (emergency numbers),
    /// followed by Canadian embassies and consulates, which are left out.
    private static func emergencyBlocks(fromOfficesHTML html: String) -> [AdviceSection.Block] {
        guard let start = html.range(of: "Local services</h3>") else { return [] }
        let rest = html[start.upperBound...]
        let end = rest.range(of: "<h3")?.lowerBound ?? rest.endIndex
        let blocks = AdviceSection.sections(fromHTML: String(rest[..<end])).flatMap(\.blocks)
        return blocks
            // "Emergency services" is the only heading and repeats the section title.
            .filter { $0 != .subheading("Emergency services") }
            .map(\.withTappablePhoneNumbers)
    }
}

extension AdviceSection.Block {

    /// Short numbers (2 to 5 digits, like 112 or 1669) become `tel:` links.
    /// Longer ones are left alone; in this section they're helplines written
    /// with spaces, which aren't worth guessing at.
    fileprivate var withTappablePhoneNumbers: AdviceSection.Block {
        switch self {
        case .paragraph(let text):
            return .paragraph(Self.linkingNumbers(in: text))
        case .bullet(let text, let depth):
            return .bullet(Self.linkingNumbers(in: text), depth: depth)
        case .subheading:
            return self
        }
    }

    private static let shortNumberPattern = try! NSRegularExpression(pattern: #"(?<![\d\-+])\d{2,5}(?![\d\-])"#)

    private static func linkingNumbers(in text: AttributedString) -> AttributedString {
        var text = text
        let plain = String(text.characters)
        let matches = shortNumberPattern.matches(in: plain, range: NSRange(plain.startIndex..., in: plain))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: plain),
                  let lower = AttributedString.Index(range.lowerBound, within: text),
                  let upper = AttributedString.Index(range.upperBound, within: text),
                  text[lower..<upper].link == nil,
                  let url = URL(string: "tel:\(plain[range])") else { continue }
            text[lower..<upper].link = url
        }
        return text
    }
}

extension Array where Element == AdviceSection {

    /// The Passport and Visas topics describe Canadian passports and Canadian
    /// visa rules. The app shows visa rules for the user's own passport on
    /// the main card instead.
    fileprivate func withoutCanadianEntryRules() -> [AdviceSection] {
        filter { section in
            guard let title = section.title?.lowercased() else { return true }
            return title != "passport" && title != "visas"
        }
        .renumbered()
    }

    /// Drops topics that only point elsewhere ("Learn about travelling with
    /// children."), which mean little without the Canadian site around them.
    fileprivate func withoutStubs() -> [AdviceSection] {
        filter { section in
            let texts = section.blocks.compactMap(\.plainText)
            return !(texts.count == 1 && texts[0].hasPrefix("Learn about"))
        }
        .renumbered()
    }

    private func renumbered() -> [AdviceSection] {
        enumerated().map { AdviceSection(id: $0.offset, title: $0.element.title, blocks: $0.element.blocks) }
    }
}

extension AdviceSection.Block {
    var hasPhoneLink: Bool {
        switch self {
        case .paragraph(let text), .bullet(let text, _):
            text.runs.contains { $0.link?.scheme == "tel" }
        case .subheading:
            false
        }
    }

    /// Text of a paragraph or bullet; nil for subheadings.
    var plainText: String? {
        switch self {
        case .paragraph(let text), .bullet(let text, _):
            String(text.characters)
        case .subheading:
            nil
        }
    }
}
