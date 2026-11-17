package com.pathos.tellus.guide.advisories

import java.text.BreakIterator
import java.util.Locale

/** Text with links, kept free of Compose types so the parsing stays unit-testable. */
data class AdviceText(val text: String, val links: List<Link> = emptyList()) {
    /** [url] covers [start] until [end] in [text]. */
    data class Link(val start: Int, val end: Int, val url: String)
}

/**
 * One topic from a section of the travel advice, such as Drugs or Driving in
 * "Laws and culture". [title] is null for the general advice that comes
 * before the first topic. Ported from iOS `AdviceSection`.
 */
data class AdviceSection(val id: Int, val title: String?, val blocks: List<Block>) {
    sealed interface Block {
        data class Paragraph(val text: AdviceText) : Block
        data class Bullet(val text: AdviceText, val depth: Int) : Block
        data class Subheading(val text: String) : Block

        val isText: Boolean get() = this !is Subheading

        /** Text of a paragraph or bullet; null for subheadings. */
        val plainText: String?
            get() = when (this) {
                is Paragraph -> text.text
                is Bullet -> text.text
                is Subheading -> null
            }

        val hasPhoneLink: Boolean
            get() = when (this) {
                is Paragraph -> text.links.any { it.url.startsWith("tel:") }
                is Bullet -> text.links.any { it.url.startsWith("tel:") }
                is Subheading -> false
            }
    }

    companion object {
        /** Splits the advice HTML into topics at each `<h3>`. */
        fun fromHtml(html: String): List<AdviceSection> = AdviceHtmlParser().parse(html)
    }
}

/**
 * The advice is written for Canadians. This drops what only applies to them:
 * child abduction (about treaties with Canada), prisoner transfers to Canada,
 * and the consular parts of dual citizenship, keeping whether the country
 * recognises dual citizenship and its own rules for it.
 */
fun List<AdviceSection>.withoutCanadaSpecificAdvice(): List<AdviceSection> =
    mapNotNull { section ->
        val title = section.title?.lowercase() ?: return@mapNotNull section
        if ("child abduction" in title || "canad" in title) return@mapNotNull null
        if ("transfer" in title && listOf("prison", "sentenced", "offender").any { it in title }) return@mapNotNull null
        if ("dual citizen" !in title) return@mapNotNull section
        var blocks = section.blocks.mapNotNull { it.withoutCanadianServices() }
        // Drop subheadings left with nothing under them, like a "Useful links"
        // whose only link went to the Canadian government.
        blocks = blocks.filterIndexed { index, block -> block.isText || blocks.getOrNull(index + 1)?.isText == true }
        if (blocks.any { it.isText }) section.copy(blocks = blocks) else null
    }.renumbered()

fun List<AdviceSection>.renumbered(): List<AdviceSection> = mapIndexed { index, section -> section.copy(id = index) }

/**
 * The block without sentences about Canadian consular help ("our ability to
 * offer you consular services…"), or null if nothing else is left. Blocks
 * linking to the Canadian government are dropped whole.
 */
private fun AdviceSection.Block.withoutCanadianServices(): AdviceSection.Block? {
    val text = when (this) {
        is AdviceSection.Block.Subheading -> return this
        is AdviceSection.Block.Paragraph -> text
        is AdviceSection.Block.Bullet -> text
    }
    if (text.links.any { link -> hostOf(link.url)?.endsWith("gc.ca") == true }) return null

    val sentences = sentences(text.text)
    val kept = sentences.filterNot(::isAboutCanadianServices)
    if (kept.size == sentences.size) return this
    if (kept.isEmpty()) return null
    // Rebuilt as plain text; these paragraphs don't carry links of their own.
    val rebuilt = AdviceText(kept.joinToString(" "))
    return when (this) {
        is AdviceSection.Block.Bullet -> AdviceSection.Block.Bullet(rebuilt, depth)
        else -> AdviceSection.Block.Paragraph(rebuilt)
    }
}

private fun hostOf(url: String): String? =
    Regex("^[a-zA-Z][a-zA-Z0-9+.-]*://([^/:?#]+)").find(url)?.groupValues?.get(1)?.lowercase()

private fun sentences(text: String): List<String> {
    val iterator = BreakIterator.getSentenceInstance(Locale.ENGLISH).apply { setText(text) }
    val result = mutableListOf<String>()
    var start = iterator.first()
    var end = iterator.next()
    while (end != BreakIterator.DONE) {
        text.substring(start, end).trim().takeIf { it.isNotEmpty() }?.let(result::add)
        start = end
        end = iterator.next()
    }
    return result
}

private fun isAboutCanadianServices(sentence: String): Boolean {
    val words = sentence.lowercase().split(Regex("[^\\p{L}]+"))
    return "consular" in words || words.any { it == "we" || it == "us" || it == "our" }
}

/** A small HTML reader for the advisory markup, ported from iOS `AdviceHTMLParser`. */
private class AdviceHtmlParser {
    private enum class Heading { TOPIC, SUBHEADING }

    /** A run of inline text, with the link it sits in, if any. */
    private data class Segment(val text: String, val url: String?)

    private val sections = mutableListOf<MutableSection>()
    private val inline = mutableListOf<Segment>()
    private var heading: Heading? = null
    private var listDepth = 0
    private val listItems = mutableListOf<Int>()
    private val openLinks = mutableListOf<String?>()

    private class MutableSection(val title: String?, val blocks: MutableList<AdviceSection.Block> = mutableListOf())

    fun parse(rawHtml: String): List<AdviceSection> {
        val html = COMMENT.replace(rawHtml, "")
        var position = 0
        for (match in TAG.findAll(html)) {
            appendText(html.substring(position, match.range.first))
            consume(match.groupValues[2].lowercase(), isClosing = match.groupValues[1].isNotEmpty(), attributes = match.groupValues[3])
            position = match.range.last + 1
        }
        appendText(html.substring(position))
        flush()
        return sections
            .filter { it.blocks.isNotEmpty() }
            .mapIndexed { index, section -> AdviceSection(index, section.title, section.blocks.toList()) }
    }

    private fun consume(tag: String, isClosing: Boolean, attributes: String) {
        when (tag) {
            "h3", "h4", "h5", "summary" -> {
                flush()
                heading = if (isClosing) null else if (tag == "h3") Heading.TOPIC else Heading.SUBHEADING
            }
            "li" -> {
                flush()
                if (isClosing) {
                    closeListItem()
                } else if (listItems.lastOrNull() != listDepth) {
                    // An opening item at the same depth also closes an omitted end tag.
                    listItems += listDepth
                }
            }
            "ul", "ol" -> {
                flush()
                if (isClosing) {
                    closeListItem()
                    listDepth = maxOf(0, listDepth - 1)
                } else {
                    listDepth++
                }
            }
            "p", "div", "details", "section" -> flush()
            "br" -> inline += Segment(" ", currentLink())
            "a" -> if (isClosing) {
                openLinks.removeLastOrNull()
            } else {
                val match = HREF.find(attributes)
                val href = (match?.groupValues?.get(1)?.ifEmpty { null } ?: match?.groupValues?.get(2))
                    ?.let(::linkDestination)
                openLinks += if (heading == null) href else null
            }
        }
    }

    private fun closeListItem() {
        if (listItems.lastOrNull() == listDepth) listItems.removeAt(listItems.lastIndex)
    }

    private fun currentLink(): String? = openLinks.lastOrNull { it != null }

    private fun appendText(raw: String) {
        if (raw.isNotEmpty()) inline += Segment(decodeEntities(raw), currentLink())
    }

    private fun appendBlock(block: AdviceSection.Block) {
        if (sections.isEmpty()) sections += MutableSection(null)
        sections.last().blocks += block
    }

    /**
     * Collapses whitespace across the pending segments (trimming the ends)
     * while keeping each link's span, then emits the text as a block.
     */
    private fun flush() {
        val out = StringBuilder()
        val links = mutableListOf<AdviceText.Link>()
        var pendingSpace = false
        for (segment in inline) {
            var start = -1
            for (char in segment.text) {
                if (char.isWhitespace()) {
                    pendingSpace = true
                    continue
                }
                if (pendingSpace && out.isNotEmpty()) out.append(' ')
                pendingSpace = false
                if (start < 0) start = out.length
                out.append(char)
            }
            if (start >= 0 && segment.url != null) {
                val last = links.lastOrNull()
                // Adjacent runs of the same link (split by <br> or entities) become one span.
                if (last != null && last.url == segment.url && last.end >= start - 1) {
                    links[links.lastIndex] = last.copy(end = out.length)
                } else {
                    links += AdviceText.Link(start, out.length, segment.url)
                }
            }
        }
        inline.clear()
        val text = out.toString()
        if (text.isEmpty()) return
        when (heading) {
            Heading.TOPIC -> sections += MutableSection(text)
            Heading.SUBHEADING -> appendBlock(AdviceSection.Block.Subheading(text))
            null -> {
                val content = AdviceText(text, links)
                val depth = listItems.lastOrNull()
                appendBlock(
                    if (depth != null) AdviceSection.Block.Bullet(content, maxOf(0, depth - 1))
                    else AdviceSection.Block.Paragraph(content),
                )
            }
        }
    }

    private companion object {
        val COMMENT = Regex("<!--.*?-->", RegexOption.DOT_MATCHES_ALL)
        val TAG = Regex("<(/?)([a-zA-Z0-9]+)([^>]*)>")
        val HREF = Regex("(?i)(?:^|\\s)href\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')")

        /** Absolute URL for a link, or null for in-page anchors. */
        fun linkDestination(rawHref: String): String? {
            val href = decodeEntities(rawHref).trim()
            if (href.isEmpty() || href.startsWith("#")) return null
            if (href.startsWith("/")) return "https://travel.gc.ca$href"
            return href
        }
    }
}

/**
 * HTML's named entities for Latin-1 (U+00A0 to U+00FF, in order) plus common
 * punctuation. That covers the accented place names and currency signs the
 * advice uses.
 */
private val namedEntities: Map<String, String> = run {
    val latin1 = (
        "nbsp iexcl cent pound curren yen brvbar sect uml copy ordf laquo not shy reg macr " +
            "deg plusmn sup2 sup3 acute micro para middot cedil sup1 ordm raquo frac14 frac12 frac34 iquest " +
            "Agrave Aacute Acirc Atilde Auml Aring AElig Ccedil Egrave Eacute Ecirc Euml Igrave Iacute Icirc Iuml " +
            "ETH Ntilde Ograve Oacute Ocirc Otilde Ouml times Oslash Ugrave Uacute Ucirc Uuml Yacute THORN szlig " +
            "agrave aacute acirc atilde auml aring aelig ccedil egrave eacute ecirc euml igrave iacute icirc iuml " +
            "eth ntilde ograve oacute ocirc otilde ouml divide oslash ugrave uacute ucirc uuml yacute thorn yuml"
        ).split(' ')
    val entities = latin1.withIndex().associate { (offset, name) -> name to (0xA0 + offset).toChar().toString() }.toMutableMap()
    entities["nbsp"] = " "
    entities += mapOf(
        "amp" to "&", "lt" to "<", "gt" to ">", "quot" to "\"", "apos" to "'",
        "lsquo" to "\u2018", "rsquo" to "\u2019", "sbquo" to "\u201A",
        "ldquo" to "\u201C", "rdquo" to "\u201D", "bdquo" to "\u201E",
        "ndash" to "\u2013", "mdash" to "\u2014", "hellip" to "\u2026", "bull" to "\u2022",
        "euro" to "\u20AC", "trade" to "\u2122", "permil" to "\u2030",
        "lsaquo" to "\u2039", "rsaquo" to "\u203A", "dagger" to "\u2020", "Dagger" to "\u2021",
        "OElig" to "\u0152", "oelig" to "\u0153", "Scaron" to "\u0160", "scaron" to "\u0161",
        "Yuml" to "\u0178", "fnof" to "\u0192", "circ" to "\u02C6", "tilde" to "\u02DC",
        "ensp" to " ", "emsp" to " ", "thinsp" to " ", "zwnj" to "\u200C", "zwj" to "\u200D",
        "lrm" to "\u200E", "rlm" to "\u200F",
    )
    entities
}

internal fun decodeEntities(text: String): String {
    if ('&' !in text) return text
    val result = StringBuilder()
    var index = 0
    while (true) {
        val ampersand = text.indexOf('&', index)
        if (ampersand < 0) break
        result.append(text, index, ampersand)
        val semicolon = text.indexOf(';', ampersand).takeIf { it in ampersand + 1..ampersand + 9 }
        val decoded = semicolon?.let { decodeEntity(text.substring(ampersand + 1, it)) }
        if (semicolon != null && decoded != null) {
            result.append(decoded)
            index = semicolon + 1
        } else {
            result.append('&')
            index = ampersand + 1
        }
    }
    return result.append(text, index, text.length).toString()
}

private fun decodeEntity(name: String): String? {
    if (name.startsWith("#")) {
        val digits = name.drop(1)
        val value = if (digits.lowercase().startsWith("x")) digits.drop(1).toIntOrNull(16) else digits.toIntOrNull()
        return value?.takeIf { Character.isValidCodePoint(it) }?.let { String(Character.toChars(it)) }
    }
    return namedEntities[name]
}
