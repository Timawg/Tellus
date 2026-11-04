//
//  RecentEvents.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2026-11-04.
//

import Foundation

/// A dated event from Wikipedia's "<year> in <country>" article.
struct RecentEvent: Equatable, Identifiable {
    let id: Int
    let date: Date
    let text: String
}

/// The recent events for one country, and the article they came from.
struct RecentEvents: Equatable {
    let events: [RecentEvent]
    let articleTitle: String

    var articleURL: URL? {
        let path = articleTitle.replacingOccurrences(of: " ", with: "_")
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        return path.flatMap { URL(string: "https://en.wikipedia.org/wiki/\($0)") }
    }
}

/// Reads the "Events" section of a "<year> in <country>" article's wikitext.
///
/// Entries are bullet lines such as `* 25 October – A bus collides…`, with
/// variations: US-style dates ("October 25"), date ranges ("6–22 February"),
/// `{{snd}}` as the separator, and a date on its own line followed by `**`
/// sub-items for several events on one day. Undated lines (ongoing topics)
/// are skipped.
enum WikipediaEventsParser {

    private static let months = [
        "january", "february", "march", "april", "may", "june",
        "july", "august", "september", "october", "november", "december",
    ]

    private static let monthPattern = "(January|February|March|April|May|June|July|August|September|October|November|December)"
    /// "25 October", "6–22 February", "30 January – 2 February", "October 25", "October 6–8".
    private static let datePattern = try! NSRegularExpression(pattern: """
        ^\\s*(?:(\\d{1,2})(?:\\s*[–—-]\\s*\\d{1,2})?\\s+\(monthPattern)|\(monthPattern)\\s+(\\d{1,2})(?!\\d)(?:\\s*[–—-]\\s*\\d{1,2}(?![\\d\\s]*\\w))?)\
        (?:\\s*[–—-]\\s*(?:\\d{1,2}\\s+\(monthPattern)|\(monthPattern)\\s+\\d{1,2}(?!\\d)))?\
        \\s*(?:[–—:-]|\\{\\{\\s*(?:snd|ndash|spaced ndash|mdash)\\s*\\}\\})?\\s*
        """, options: [.caseInsensitive])

    static func events(fromWikitext wikitext: String, year: Int, now: Date = Date(), calendar: Calendar = .current) -> [RecentEvent] {
        guard let section = eventsSection(of: wikitext) else { return [] }

        var events: [(date: Date, order: Int, text: String)] = []
        var currentDate: Date?   // For "**" items under a date-only line.
        var order = 0

        for rawLine in section.components(separatedBy: .newlines) {
            guard rawLine.hasPrefix("*") else {
                if rawLine.hasPrefix("=") { currentDate = nil }
                continue
            }
            let depth = rawLine.prefix { $0 == "*" }.count
            let body = removingFileLinks(from: String(rawLine.dropFirst(depth)))
            if isLinkOnly(body), unlinked(body).contains(" at the ") {
                // "6–22 February – [[Kenya at the 2026 Winter Olympics]]" is
                // a country taking part, not something happening there.
                // Other bare links ("[[2026 New Caledonian legislative
                // election]]") are kept as the event's text.
                if depth == 1 { currentDate = nil }
                continue
            }
            let plainForDate = unlinked(body)

            if let (date, rest) = leadingDate(in: plainForDate, year: year, calendar: calendar) {
                if depth == 1 { currentDate = date }
                let text = cleaned(rest)
                if isMeaningful(text) {
                    events.append((date, order, text))
                    order += 1
                }
            } else if depth > 1, let date = currentDate {
                let text = cleaned(body)
                if isMeaningful(text) {
                    events.append((date, order, text))
                    order += 1
                }
            } else if depth == 1 {
                currentDate = nil
            }
        }

        let today = calendar.startOfDay(for: now)
        return events
            .filter { $0.date <= today }   // Pages also list scheduled events.
            .sorted { $0.date != $1.date ? $0.date > $1.date : $0.order < $1.order }
            .enumerated()
            .map { RecentEvent(id: $0.offset, date: $0.element.date, text: $0.element.text) }
    }

    // MARK: Section

    /// The text between "== Events ==" and the next level-2 heading.
    static func eventsSection(of wikitext: String) -> String? {
        let lines = wikitext.components(separatedBy: .newlines)
        guard let start = lines.firstIndex(where: { isLevel2Heading($0, named: "events") }) else { return nil }
        let rest = lines[(start + 1)...]
        let end = rest.firstIndex(where: { isLevel2Heading($0, named: nil) }) ?? rest.endIndex
        return rest[..<end].joined(separator: "\n")
    }

    private static func isLevel2Heading(_ line: String, named name: String?) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("=="), !trimmed.hasPrefix("==="), trimmed.hasSuffix("==") else { return false }
        guard let name else { return true }
        return trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "= ")).lowercased() == name
    }

    // MARK: Dates

    private static func leadingDate(in text: String, year: Int, calendar: Calendar) -> (Date, String)? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = datePattern.firstMatch(in: text, range: range) else { return nil }
        func group(_ index: Int) -> String? {
            Range(match.range(at: index), in: text).map { String(text[$0]) }
        }
        let day = group(1) ?? group(4)
        let monthName = group(2) ?? group(3)
        guard let day = day.flatMap(Int.init),
              let month = monthName.flatMap({ months.firstIndex(of: $0.lowercased()) }).map({ $0 + 1 }),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              let matchRange = Range(match.range, in: text) else { return nil }
        return (date, String(text[matchRange.upperBound...]))
    }

    // MARK: Cleaning

    /// Text worth showing: prose, not just a link to another article
    /// ("Colombia at the 2026 Winter Olympics") or a stray fragment.
    private static func isMeaningful(_ text: String) -> Bool {
        text.count >= 25 && text.contains(" ")
    }

    /// A date (or nothing) followed only by a single wikilink.
    private static func isLinkOnly(_ body: String) -> Bool {
        var text = body.replacingOccurrences(of: #"<ref[^>]*/>"#, with: "", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: #"<ref[^>]*>.*?</ref>"#, with: "", options: [.regularExpression, .caseInsensitive])
        text = removingTemplates(from: text)
        return text.range(of: #"^[\s\d\p{L}–—-]*?[\s–—:-]*\[\[[^\[\]]+\]\][\s.]*$"#, options: .regularExpression) != nil
            && unlinked(text).trimmingCharacters(in: .whitespaces).count < 120
            && text.components(separatedBy: "[[").count == 2
            && text.range(of: #"^\s*\[\[|[–—:-]\s*\[\["#, options: .regularExpression) != nil
    }

    /// Wikilinks replaced by their visible text, so dates inside links
    /// ("[[25 October]]") can be read.
    private static func unlinked(_ text: String) -> String {
        text.replacingOccurrences(of: #"\[\[(?:[^\]|]*\|)?([^\]]*)\]\]"#, with: "$1", options: .regularExpression)
    }

    /// Removes `[[File:…]]` and `[[Image:…]]` pictures, whose captions can
    /// contain links of their own.
    private static func removingFileLinks(from text: String) -> String {
        var text = text
        while let start = text.range(of: #"\[\[(?:File|Image):"#, options: [.regularExpression, .caseInsensitive]) {
            var depth = 0
            var cursor = start.lowerBound
            var end = text.endIndex
            while cursor < text.endIndex {
                if text[cursor...].hasPrefix("[[") {
                    depth += 1
                    cursor = text.index(cursor, offsetBy: 2)
                } else if text[cursor...].hasPrefix("]]") {
                    depth -= 1
                    cursor = text.index(cursor, offsetBy: 2)
                    if depth == 0 { end = cursor; break }
                } else {
                    cursor = text.index(after: cursor)
                }
            }
            text.removeSubrange(start.lowerBound..<end)
        }
        return text
    }

    static func cleaned(_ wikitext: String) -> String {
        var text = wikitext
        // References and comments.
        text = text.replacingOccurrences(of: #"<!--.*?-->"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"<ref[^>]*/>"#, with: "", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: #"<ref[^>]*>.*?</ref>"#, with: "", options: [.regularExpression, .caseInsensitive])
        text = removingTemplates(from: text)
        text = unlinked(text)
        // External links: [https://… label] → label.
        text = text.replacingOccurrences(of: #"\[https?://[^\s\]]+\s*([^\]]*)\]"#, with: "$1", options: .regularExpression)
        // Bold and italics, remaining HTML tags.
        text = text.replacingOccurrences(of: "'''", with: "").replacingOccurrences(of: "''", with: "")
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&ndash;", with: "–")
            .replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s+([,.;:])"#, with: "$1", options: .regularExpression)
        return text.trimmingCharacters(in: CharacterSet(charactersIn: " –—-:"))
    }

    /// Removes `{{…}}` templates, keeping the useful parts of the few that
    /// carry text: `{{convert|5|km}}` → "5 km", `{{nowrap|x}}` → "x", and
    /// dash templates → "–".
    private static func removingTemplates(from text: String) -> String {
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            if text[index...].hasPrefix("{{") {
                // Find the matching close, allowing nesting.
                var depth = 0
                var cursor = index
                var end: String.Index?
                while cursor < text.endIndex {
                    if text[cursor...].hasPrefix("{{") {
                        depth += 1
                        cursor = text.index(cursor, offsetBy: 2)
                    } else if text[cursor...].hasPrefix("}}") {
                        depth -= 1
                        cursor = text.index(cursor, offsetBy: 2)
                        if depth == 0 { end = cursor; break }
                    } else {
                        cursor = text.index(after: cursor)
                    }
                }
                guard let end else { break }
                let inner = String(text[text.index(index, offsetBy: 2)..<text.index(end, offsetBy: -2)])
                result += replacement(forTemplate: inner)
                index = end
            } else {
                result.append(text[index])
                index = text.index(after: index)
            }
        }
        return result
    }

    private static func replacement(forTemplate inner: String) -> String {
        let parts = inner.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let name = parts.first?.lowercased() ?? ""
        switch name {
        case "snd", "ndash", "spaced ndash", "mdash", "spnd":
            return " – "
        case "convert", "cvt":
            return parts.count >= 3 ? " \(parts[1]) \(parts[2]) " : ""
        case "nowrap", "nobr", "lang", "transl":
            return parts.last.map(removingTemplates(from:)) ?? ""
        default:
            return ""
        }
    }
}
