import Foundation

extension AdviceSection {
    /// Splits the advice HTML into topics at each <h3>.
    static func sections(fromHTML html: String) -> [AdviceSection] {
        var parser = AdviceHTMLParser()
        return parser.parse(html)
    }
}

private struct AdviceHTMLParser {
    private enum Heading {
        case topic, subheading
    }

    private var sections: [AdviceSection] = []
    private var inline = ""
    private var heading: Heading?
    private var listDepth = 0
    private var listItems: [Int] = []
    private var openLinks: [String?] = []

    mutating func parse(_ rawHTML: String) -> [AdviceSection] {
        let html = rawHTML.replacing(#/(?s)<!--.*?-->/#, with: "")
        let tagPattern = #/<(/?)([a-zA-Z0-9]+)([^>]*)>/#
        var position = html.startIndex
        for match in html.matches(of: tagPattern) {
            appendText(html[position..<match.range.lowerBound])
            consume(tag: match.2.lowercased(), isClosing: !match.1.isEmpty, attributes: match.3)
            position = match.range.upperBound
        }
        appendText(html[position...])
        flush()
        return sections
            .filter { !$0.blocks.isEmpty }
            .enumerated()
            .map { AdviceSection(id: $0.offset, title: $0.element.title, blocks: $0.element.blocks) }
    }

    private mutating func consume(tag: String, isClosing: Bool, attributes: Substring) {
        switch tag {
        case "h3", "h4", "h5", "summary":
            flush()
            heading = isClosing ? nil : (tag == "h3" ? .topic : .subheading)
        case "li":
            updateListItem(isClosing: isClosing)
        case "ul", "ol":
            updateList(isClosing: isClosing)
        case "p", "div", "details", "section":
            flush()
        case "br":
            inline += " "
        case "a":
            updateLink(isClosing: isClosing, attributes: attributes)
        default:
            break
        }
    }

    private mutating func updateList(isClosing: Bool) {
        flush()
        if isClosing {
            closeListItem()
            listDepth = max(0, listDepth - 1)
        } else {
            listDepth += 1
        }
    }

    private mutating func updateListItem(isClosing: Bool) {
        flush()
        if isClosing {
            closeListItem()
        } else if listItems.last != listDepth {
            // An opening item at the same depth also closes an omitted end tag.
            listItems.append(listDepth)
        }
    }

    private mutating func closeListItem() {
        if listItems.last == listDepth { listItems.removeLast() }
    }

    private mutating func updateLink(isClosing: Bool, attributes: Substring) {
        if isClosing {
            if let href = openLinks.popLast() ?? nil { inline += "](<\(href)>)" }
            return
        }
        let hrefPattern = #/(?i)(?:^|\s)href\s*=\s*(?:"([^"]*)"|'([^']*)')/#
        let match = attributes.firstMatch(of: hrefPattern)
        let href = (match?.1 ?? match?.2).flatMap { Self.linkDestination(for: String($0)) }
        openLinks.append(heading == nil ? href : nil)
        if heading == nil, href != nil { inline += "[" }
    }

    private mutating func appendText(_ raw: Substring) {
        let text = Self.decodeEntities(String(raw))
        inline += heading == nil ? Self.escapeMarkdown(text) : text
    }

    private mutating func append(_ block: AdviceSection.Block) {
        if sections.isEmpty {
            sections.append(AdviceSection(id: 0, title: nil, blocks: []))
        }
        sections[sections.count - 1].blocks.append(block)
    }

    private mutating func flush() {
        let text = inline.replacing(#/\s+/#, with: " ").trimmingCharacters(in: .whitespaces)
        inline = ""
        guard !text.isEmpty else { return }
        switch heading {
        case .topic:
            sections.append(AdviceSection(id: sections.count, title: text, blocks: []))
        case .subheading:
            append(.subheading(text))
        case nil:
            let attributed = (try? AttributedString(
                markdown: text,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )) ?? AttributedString(text)
            if let depth = listItems.last {
                append(.bullet(attributed, depth: max(0, depth - 1)))
            } else {
                append(.paragraph(attributed))
            }
        }
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
            "lrm": "\u{200E}", "rlm": "\u{200F}"
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
