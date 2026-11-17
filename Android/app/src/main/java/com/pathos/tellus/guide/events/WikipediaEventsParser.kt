package com.pathos.tellus.guide.events

import java.net.URLEncoder
import java.time.LocalDate

/** A dated event from Wikipedia's "<year> in <country>" article. */
data class RecentEvent(val id: Int, val date: LocalDate, val text: String)

/** The recent events for one country, and the article they came from. */
data class RecentEvents(val events: List<RecentEvent>, val articleTitle: String) {
    val articleUrl: String
        get() = "https://en.wikipedia.org/wiki/" + URLEncoder.encode(articleTitle.replace(' ', '_'), "UTF-8")
            .replace("+", "%20")
}

/**
 * Reads the "Events" section of a "<year> in <country>" article's wikitext,
 * ported from iOS `WikipediaEventsParser`.
 *
 * Entries are bullet lines such as `* 25 October – A bus collides…`, with
 * variations: US-style dates ("October 25"), date ranges ("6–22 February"),
 * `{{snd}}` as the separator, and a date on its own line followed by `**`
 * sub-items for several events on one day. Undated lines (ongoing topics)
 * are skipped.
 */
object WikipediaEventsParser {

    private val months = listOf(
        "january", "february", "march", "april", "may", "june",
        "july", "august", "september", "october", "november", "december",
    )

    private const val MONTH = "(January|February|March|April|May|June|July|August|September|October|November|December)"

    /** "25 October", "6–22 February", "30 January – 2 February", "October 25", "October 6–8". */
    private val datePattern = Regex(
        "^\\s*(?:(\\d{1,2})(?:\\s*[–—-]\\s*\\d{1,2})?\\s+$MONTH|$MONTH\\s+(\\d{1,2})(?!\\d)(?:\\s*[–—-]\\s*\\d{1,2}(?![\\d\\s]*\\w))?)" +
            "(?:\\s*[–—-]\\s*(?:\\d{1,2}\\s+$MONTH|$MONTH\\s+\\d{1,2}(?!\\d)))?" +
            "\\s*(?:[–—:-]|\\{\\{\\s*(?:snd|ndash|spaced ndash|mdash)\\s*\\}\\})?\\s*",
        RegexOption.IGNORE_CASE,
    )

    fun events(wikitext: String, year: Int, today: LocalDate): List<RecentEvent> {
        val section = eventsSection(wikitext) ?: return emptyList()

        data class Found(val date: LocalDate, val order: Int, val text: String)

        val events = mutableListOf<Found>()
        var currentDate: LocalDate? = null // For "**" items under a date-only line.
        var order = 0

        for (rawLine in section.lines()) {
            if (!rawLine.startsWith("*")) {
                if (rawLine.startsWith("=")) currentDate = null
                continue
            }
            val depth = rawLine.takeWhile { it == '*' }.length
            val body = removingFileLinks(rawLine.drop(depth))
            if (isLinkOnly(body) && unlinked(body).contains(" at the ")) {
                // "6–22 February – [[Kenya at the 2026 Winter Olympics]]" is a
                // country taking part, not something happening there. Other
                // bare links are kept as the event's text.
                if (depth == 1) currentDate = null
                continue
            }
            val leading = leadingDate(unlinked(body), year)
            if (leading != null) {
                val (date, rest) = leading
                if (depth == 1) currentDate = date
                val text = cleaned(rest)
                if (isMeaningful(text)) events += Found(date, order++, text)
            } else if (depth > 1 && currentDate != null) {
                val text = cleaned(body)
                if (isMeaningful(text)) events += Found(currentDate, order++, text)
            } else if (depth == 1) {
                currentDate = null
            }
        }

        return events
            .filter { !it.date.isAfter(today) } // Pages also list scheduled events.
            .sortedWith(compareByDescending<Found> { it.date }.thenBy { it.order })
            .mapIndexed { index, found -> RecentEvent(index, found.date, found.text) }
    }

    /** The text between "== Events ==" and the next level-2 heading. */
    fun eventsSection(wikitext: String): String? {
        val lines = wikitext.lines()
        val start = lines.indexOfFirst { isLevel2Heading(it, "events") }
        if (start < 0) return null
        val rest = lines.drop(start + 1)
        val end = rest.indexOfFirst { isLevel2Heading(it, null) }.let { if (it < 0) rest.size else it }
        return rest.take(end).joinToString("\n")
    }

    private fun isLevel2Heading(line: String, name: String?): Boolean {
        val trimmed = line.trim(' ', '\t')
        if (!trimmed.startsWith("==") || trimmed.startsWith("===") || !trimmed.endsWith("==")) return false
        return name == null || trimmed.trim('=', ' ').lowercase() == name
    }

    private fun leadingDate(text: String, year: Int): Pair<LocalDate, String>? {
        val match = datePattern.find(text) ?: return null
        val groups = match.groupValues
        val day = (groups[1].ifEmpty { groups[4] }).toIntOrNull() ?: return null
        val monthName = groups[2].ifEmpty { groups[3] }
        val month = months.indexOf(monthName.lowercase()).takeIf { it >= 0 }?.plus(1) ?: return null
        // Lenient like Foundation's Calendar: "30 February" rolls into March.
        val date = LocalDate.of(year, month, 1).plusDays(day - 1L)
        return date to text.substring(match.range.last + 1)
    }

    /** Text worth showing: prose, not just a link to another article or a stray fragment. */
    private fun isMeaningful(text: String) = text.length >= 25 && text.contains(' ')

    private val selfClosingRef = Regex("<ref[^>]*/>", RegexOption.IGNORE_CASE)
    private val pairedRef = Regex("<ref[^>]*>.*?</ref>", RegexOption.IGNORE_CASE)
    private val linkOnly = Regex("^[\\s\\d\\p{L}–—-]*?[\\s–—:-]*\\[\\[[^\\[\\]]+\\]\\][\\s.]*$")
    private val linkAfterDate = Regex("^\\s*\\[\\[|[–—:-]\\s*\\[\\[")

    /** A date (or nothing) followed only by a single wikilink. */
    private fun isLinkOnly(body: String): Boolean {
        var text = selfClosingRef.replace(body, "")
        text = pairedRef.replace(text, "")
        text = removingTemplates(text)
        return linkOnly.containsMatchIn(text) &&
            unlinked(text).trim(' ').length < 120 &&
            text.split("[[").size == 2 &&
            linkAfterDate.containsMatchIn(text)
    }

    private val wikilink = Regex("\\[\\[(?:[^\\]|]*\\|)?([^\\]]*)\\]\\]")

    /** Wikilinks replaced by their visible text, so dates inside links ("[[25 October]]") can be read. */
    private fun unlinked(text: String) = wikilink.replace(text, "$1")

    private val fileLinkStart = Regex("\\[\\[(?:File|Image):", RegexOption.IGNORE_CASE)

    /** Removes `[[File:…]]` and `[[Image:…]]` pictures, whose captions can contain links of their own. */
    private fun removingFileLinks(input: String): String {
        var text = input
        while (true) {
            val start = fileLinkStart.find(text)?.range?.first ?: return text
            var depth = 0
            var cursor = start
            var end = text.length
            while (cursor < text.length) {
                when {
                    text.startsWith("[[", cursor) -> { depth++; cursor += 2 }
                    text.startsWith("]]", cursor) -> {
                        depth--
                        cursor += 2
                        if (depth == 0) { end = cursor; break }
                    }
                    else -> cursor++
                }
            }
            text = text.removeRange(start, end)
        }
    }

    private val comment = Regex("<!--.*?-->")
    private val externalLink = Regex("\\[https?://[^\\s\\]]+\\s*([^\\]]*)\\]")
    private val htmlTag = Regex("<[^>]+>")
    private val whitespace = Regex("\\s+")
    private val spaceBeforePunctuation = Regex("\\s+([,.;:])")

    fun cleaned(wikitext: String): String {
        var text = comment.replace(wikitext, "")
        text = selfClosingRef.replace(text, "")
        text = pairedRef.replace(text, "")
        text = removingTemplates(text)
        text = unlinked(text)
        // External links: [https://… label] → label.
        text = externalLink.replace(text, "$1")
        // Bold and italics, remaining HTML tags.
        text = text.replace("'''", "").replace("''", "")
        text = htmlTag.replace(text, "")
        text = text.replace("&nbsp;", " ").replace("&ndash;", "–").replace("&amp;", "&")
        text = whitespace.replace(text, " ")
        text = spaceBeforePunctuation.replace(text, "$1")
        return text.trim(' ', '–', '—', '-', ':')
    }

    /**
     * Removes `{{…}}` templates, keeping the useful parts of the few that
     * carry text: `{{convert|5|km}}` → "5 km", `{{nowrap|x}}` → "x", and dash
     * templates → "–".
     */
    private fun removingTemplates(text: String): String {
        val result = StringBuilder()
        var index = 0
        while (index < text.length) {
            if (text.startsWith("{{", index)) {
                // Find the matching close, allowing nesting.
                var depth = 0
                var cursor = index
                var end = -1
                while (cursor < text.length) {
                    when {
                        text.startsWith("{{", cursor) -> { depth++; cursor += 2 }
                        text.startsWith("}}", cursor) -> {
                            depth--
                            cursor += 2
                            if (depth == 0) { end = cursor; break }
                        }
                        else -> cursor++
                    }
                }
                if (end < 0) break
                result.append(replacement(text.substring(index + 2, end - 2)))
                index = end
            } else {
                result.append(text[index])
                index++
            }
        }
        return result.toString()
    }

    private fun replacement(inner: String): String {
        val parts = inner.split("|").map { it.trim() }
        return when (parts.first().lowercase()) {
            "snd", "ndash", "spaced ndash", "mdash", "spnd" -> " – "
            "convert", "cvt" -> if (parts.size >= 3) " ${parts[1]} ${parts[2]} " else ""
            "nowrap", "nobr", "lang", "transl" -> removingTemplates(parts.last())
            else -> ""
        }
    }
}
