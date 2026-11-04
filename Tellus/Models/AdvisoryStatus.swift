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
        case bullet(AttributedString)
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
        case .bullet(let text):
            (attributed, makeBlock) = (text, AdviceSection.Block.bullet)
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

extension AdviceSection {

    private static let tagPattern = try! NSRegularExpression(pattern: #"<(/?)([a-zA-Z0-9]+)([^>]*)>"#)
    private static let hrefPattern = try! NSRegularExpression(pattern: #"href\s*=\s*"([^"]*)""#)
    private static let commentPattern = try! NSRegularExpression(pattern: #"<!--.*?-->"#, options: .dotMatchesLineSeparators)

    /// Splits the advice HTML into topics on its `<h3>` headings. The API uses a
    /// small set of tags (p, ul/li, h3/h4, details/summary, a, b, i, span);
    /// `<h4>`, `<h5>` and `<summary>` become subheadings, links are kept, and
    /// other tags are dropped, keeping their text.
    static func sections(fromHTML rawHTML: String) -> [AdviceSection] {
        // The health advice carries HTML comments marking where its parts start and end.
        let html = commentPattern.stringByReplacingMatches(
            in: rawHTML,
            range: NSRange(location: 0, length: (rawHTML as NSString).length),
            withTemplate: ""
        )
        var sections: [AdviceSection] = []
        var inline = ""             // Markdown for the paragraph, bullet or heading being read
        var heading: Int?           // 3 inside <h3>, 4 inside <h4>, <h5> or <summary>
        var inListItem = false
        var openLinks: [String?] = []

        func append(_ block: Block) {
            if sections.isEmpty {
                sections.append(AdviceSection(id: 0, title: nil, blocks: []))
            }
            sections[sections.count - 1].blocks.append(block)
        }

        func flush() {
            let text = inline
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            inline = ""
            guard !text.isEmpty else { return }
            switch heading {
            case 3:
                sections.append(AdviceSection(id: sections.count, title: text, blocks: []))
            case 4:
                append(.subheading(text))
            default:
                let attributed = (try? AttributedString(
                    markdown: text,
                    options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                )) ?? AttributedString(text)
                append(inListItem ? .bullet(attributed) : .paragraph(attributed))
            }
        }

        func appendText(_ raw: Substring) {
            let text = decodeEntities(String(raw))
            // Headings are shown as plain text; everything else is Markdown.
            inline += heading == nil ? escapeMarkdown(text) : text
        }

        let nsHTML = html as NSString
        var position = 0
        for match in tagPattern.matches(in: html, range: NSRange(location: 0, length: nsHTML.length)) {
            appendText(Substring(nsHTML.substring(with: NSRange(location: position, length: match.range.location - position))))
            position = match.range.location + match.range.length

            let isClosing = match.range(at: 1).length > 0
            let tag = nsHTML.substring(with: match.range(at: 2)).lowercased()
            switch (tag, isClosing) {
            case ("h3", false), ("h4", false), ("h5", false), ("summary", false):
                flush()
                heading = tag == "h3" ? 3 : 4
            case ("h3", true), ("h4", true), ("h5", true), ("summary", true):
                flush()
                heading = nil
            case ("li", false):
                flush()
                inListItem = true
            case ("li", true):
                flush()
                inListItem = false
            case ("p", _), ("ul", _), ("ol", _), ("div", _), ("details", _), ("section", _):
                flush()
            case ("br", _):
                inline += " "
            case ("a", false):
                let attributes = nsHTML.substring(with: match.range(at: 3))
                let href = hrefPattern.firstMatch(in: attributes, range: NSRange(location: 0, length: (attributes as NSString).length))
                    .map { (attributes as NSString).substring(with: $0.range(at: 1)) }
                    .flatMap(linkDestination(for:))
                openLinks.append(heading == nil ? href : nil)
                if heading == nil, href != nil { inline += "[" }
            case ("a", true):
                if let href = openLinks.popLast() ?? nil { inline += "](<\(href)>)" }
            default:
                break
            }
        }
        appendText(Substring(nsHTML.substring(from: position)))
        flush()

        return sections
            .filter { !$0.blocks.isEmpty }
            .enumerated()
            .map { AdviceSection(id: $0.offset, title: $0.element.title, blocks: $0.element.blocks) }
    }

    /// Absolute URL for a link, or nil for in-page anchors.
    private static func linkDestination(for href: String) -> String? {
        let href = decodeEntities(href).trimmingCharacters(in: .whitespaces)
        if href.isEmpty || href.hasPrefix("#") { return nil }
        if href.hasPrefix("/") { return "https://travel.gc.ca" + href }
        return href.replacingOccurrences(of: ">", with: "%3E")
    }

    private static func escapeMarkdown(_ text: String) -> String {
        var escaped = ""
        for character in text {
            if "\\`*_[]<>~&!#".contains(character) { escaped.append("\\") }
            escaped.append(character)
        }
        return escaped
    }

    /// HTML's named entities for Latin-1 (U+00A0 to U+00FF, in order) plus common
    /// punctuation. That covers the accented place names and currency signs the
    /// advice uses.
    private static let namedEntities: [String: String] = {
        let latin1 = """
            nbsp iexcl cent pound curren yen brvbar sect uml copy ordf laquo not shy reg macr \
            deg plusmn sup2 sup3 acute micro para middot cedil sup1 ordm raquo frac14 frac12 frac34 iquest \
            Agrave Aacute Acirc Atilde Auml Aring AElig Ccedil Egrave Eacute Ecirc Euml Igrave Iacute Icirc Iuml \
            ETH Ntilde Ograve Oacute Ocirc Otilde Ouml times Oslash Ugrave Uacute Ucirc Uuml Yacute THORN szlig \
            agrave aacute acirc atilde auml aring aelig ccedil egrave eacute ecirc euml igrave iacute icirc iuml \
            eth ntilde ograve oacute ocirc otilde ouml divide oslash ugrave uacute ucirc uuml yacute thorn yuml
            """.split(separator: " ")
        var entities = Dictionary(uniqueKeysWithValues: latin1.enumerated().map {
            (String($0.element), String(Character(Unicode.Scalar(UInt32(0xA0 + $0.offset))!)))
        })
        entities["nbsp"] = " "
        entities.merge([
            "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
            "lsquo": "\u{2018}", "rsquo": "\u{2019}", "sbquo": "\u{201A}",
            "ldquo": "\u{201C}", "rdquo": "\u{201D}", "bdquo": "\u{201E}",
            "ndash": "\u{2013}", "mdash": "\u{2014}", "hellip": "\u{2026}", "bull": "\u{2022}",
            "euro": "\u{20AC}", "trade": "\u{2122}", "permil": "\u{2030}",
            "lsaquo": "\u{2039}", "rsaquo": "\u{203A}", "dagger": "\u{2020}", "Dagger": "\u{2021}",
            "OElig": "\u{0152}", "oelig": "\u{0153}", "Scaron": "\u{0160}", "scaron": "\u{0161}",
            "Yuml": "\u{0178}", "fnof": "\u{0192}", "circ": "\u{02C6}", "tilde": "\u{02DC}",
            "ensp": " ", "emsp": " ", "thinsp": " ", "zwnj": "\u{200C}", "zwj": "\u{200D}",
            "lrm": "\u{200E}", "rlm": "\u{200F}",
        ]) { _, new in new }
        return entities
    }()

    private static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        var index = text.startIndex
        while let ampersand = text[index...].firstIndex(of: "&") {
            result += text[index..<ampersand]
            if let semicolon = text[ampersand...].prefix(10).firstIndex(of: ";"),
               let decoded = decodeEntity(text[text.index(after: ampersand)..<semicolon]) {
                result += decoded
                index = text.index(after: semicolon)
            } else {
                result += "&"
                index = text.index(after: ampersand)
            }
        }
        return result + text[index...]
    }

    private static func decodeEntity(_ name: Substring) -> String? {
        if name.hasPrefix("#") {
            let digits = name.dropFirst()
            let value = digits.lowercased().hasPrefix("x")
                ? UInt32(digits.dropFirst(), radix: 16)
                : UInt32(digits)
            return value.flatMap(Unicode.Scalar.init).map { String(Character($0)) }
        }
        return namedEntities[String(name)]
    }
}
