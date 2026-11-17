package com.pathos.tellus.guide.advisories

import com.pathos.tellus.guide.GuideTopic

/**
 * The parts of a destination's travel advice shown in the guide, parsed once
 * from the advisory's HTML so the sheet can switch between them instantly.
 * Ported from iOS `DestinationGuide`.
 */
data class DestinationGuide(
    val advisories: List<AdviceSection>,
    val entry: List<AdviceSection>,
    val health: List<AdviceSection>,
    val laws: List<AdviceSection>,
    val climate: List<AdviceSection>,
    /** The "Local services" advice: emergency numbers and tourist helplines, with the numbers made tappable. */
    val emergency: List<AdviceSection.Block>,
    val updated: String,
    val adviceUrl: String,
) {
    fun sections(topic: GuideTopic): List<AdviceSection> = when (topic) {
        GuideTopic.OVERVIEW -> emptyList()
        GuideTopic.ENTRY -> entry
        GuideTopic.HEALTH -> health
        GuideTopic.LAWS -> laws
        GuideTopic.CLIMATE -> climate
    }

    companion object {
        /** Parsing a country's advice takes tens of milliseconds, so call this off the main thread. */
        fun from(information: AdvisoryStatus.Information) = DestinationGuide(
            advisories = AdviceSection.fromHtml(information.advisories),
            entry = AdviceSection.fromHtml(information.entryExit)
                .withoutCanadaSpecificAdvice()
                .withoutCanadianEntryRules()
                .withoutStubs(),
            health = AdviceSection.fromHtml(information.health)
                .withoutCanadaSpecificAdvice()
                .withoutStubs(),
            laws = AdviceSection.fromHtml(information.lawsCulture).withoutCanadaSpecificAdvice(),
            climate = AdviceSection.fromHtml(information.disastersClimate).withoutStubs(),
            emergency = emergencyBlocks(information.officesHtml),
            updated = information.friendlyDate,
            adviceUrl = information.travelAdviceUrl,
        )

        /**
         * The offices HTML starts with "Local services" (emergency numbers),
         * followed by Canadian embassies and consulates, which are left out.
         */
        private fun emergencyBlocks(html: String): List<AdviceSection.Block> {
            val start = html.indexOf("Local services</h3>").takeIf { it >= 0 } ?: return emptyList()
            val rest = html.substring(start + "Local services</h3>".length)
            val end = rest.indexOf("<h3").takeIf { it >= 0 } ?: rest.length
            return AdviceSection.fromHtml(rest.substring(0, end))
                .flatMap { it.blocks }
                // "Emergency services" is the only heading and repeats the section title.
                .filter { it != AdviceSection.Block.Subheading("Emergency services") }
                .map { it.withTappablePhoneNumbers() }
        }

        private val shortNumber = Regex("(?<![\\d\\-+])\\d{2,5}(?![\\d\\-])")

        /**
         * Short numbers (2 to 5 digits, like 112 or 1669) become `tel:` links.
         * Longer ones are left alone; in this section they're helplines
         * written with spaces, which aren't worth guessing at.
         */
        private fun AdviceSection.Block.withTappablePhoneNumbers(): AdviceSection.Block = when (this) {
            is AdviceSection.Block.Paragraph -> AdviceSection.Block.Paragraph(linkingNumbers(text))
            is AdviceSection.Block.Bullet -> AdviceSection.Block.Bullet(linkingNumbers(text), depth)
            is AdviceSection.Block.Subheading -> this
        }

        private fun linkingNumbers(text: AdviceText): AdviceText {
            val added = shortNumber.findAll(text.text)
                .filter { match -> text.links.none { it.start < match.range.last + 1 && match.range.first < it.end } }
                .map { AdviceText.Link(it.range.first, it.range.last + 1, "tel:${it.value}") }
                .toList()
            return if (added.isEmpty()) text else text.copy(links = (text.links + added).sortedBy { it.start })
        }

        /**
         * The Passport and Visas topics describe Canadian passports and visa
         * rules. The guide shows visa rules for the user's own passport instead.
         */
        private fun List<AdviceSection>.withoutCanadianEntryRules() =
            filter { section -> section.title?.lowercase().let { it != "passport" && it != "visas" } }.renumbered()

        /**
         * Drops topics that only point elsewhere ("Learn about travelling with
         * children."), which mean little without the Canadian site around them.
         */
        private fun List<AdviceSection>.withoutStubs() =
            filterNot { section ->
                val texts = section.blocks.mapNotNull { it.plainText }
                texts.size == 1 && texts[0].startsWith("Learn about")
            }.renumbered()
    }
}
