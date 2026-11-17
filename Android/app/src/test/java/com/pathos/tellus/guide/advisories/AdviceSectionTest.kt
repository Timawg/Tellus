package com.pathos.tellus.guide.advisories

import com.pathos.tellus.guide.advisories.AdviceSection.Block
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AdviceSectionTest {

    private fun paragraph(section: AdviceSection, index: Int) = section.blocks[index] as Block.Paragraph

    @Test
    fun splitsTopicsAtH3WithIntroductionFirst() {
        val sections = AdviceSection.fromHtml(
            """<!-- generated --><p>General   advice
               here.</p><h3>Crime</h3><h4>Petty crime</h4><p>Watch your bags.</p><h3>Empty</h3><h3>Driving</h3><p>Drive on the right.</p>""",
        )
        assertEquals(listOf(null, "Crime", "Driving"), sections.map { it.title })
        assertEquals(listOf(0, 1, 2), sections.map { it.id })
        assertEquals("General advice here.", paragraph(sections[0], 0).text.text)
        assertEquals(Block.Subheading("Petty crime"), sections[1].blocks[0])
    }

    @Test
    fun keepsLinkSpansThroughWhitespaceAndEntities() {
        val sections = AdviceSection.fromHtml(
            """<p>See   the <a href="/travelling/advisories">official&nbsp;guidance</a> and <a href="#levels">risk levels</a> &amp; <a href='https://example.com/a'>more</a>.</p>""",
        )
        val text = paragraph(sections[0], 0).text
        assertEquals("See the official guidance and risk levels & more.", text.text)
        assertEquals(
            listOf(
                AdviceText.Link(8, 25, "https://travel.gc.ca/travelling/advisories"),
                AdviceText.Link(44, 48, "https://example.com/a"),
            ),
            text.links,
        )
        assertEquals("official guidance", text.text.substring(8, 25))
    }

    @Test
    fun readsNestedListsAsBulletsWithDepth() {
        val sections = AdviceSection.fromHtml(
            "<ul><li>Northern province, excluding:<ul><li>the airport</li></ul></li><li>Coast<li>Islands</ul>",
        )
        val bullets = sections[0].blocks.map { it as Block.Bullet }
        assertEquals(listOf("Northern province, excluding:" to 0, "the airport" to 1, "Coast" to 0, "Islands" to 0), bullets.map { it.text.text to it.depth })
    }

    @Test
    fun decodesNumericAndLatinEntities() {
        val text = paragraph(AdviceSection.fromHtml("<p>Caf&eacute; &#8211; &#x2014; S&atilde;o Tom&eacute; &bogus; x</p>")[0], 0).text.text
        assertEquals("Café – — São Tomé &bogus; x", text)
    }

    @Test
    fun dropsAdviceOnlyForCanadians() {
        val sections = AdviceSection.fromHtml(
            """
            <h3>Drugs</h3><p>Penalties are severe.</p>
            <h3>International Child Abduction</h3><p>The Hague Convention…</p>
            <h3>Transfer to a Canadian prison</h3><p>Canada and X are signatories.</p>
            <h3>Dual citizenship</h3>
            <p>Dual citizenship is legally recognized in X. If you are a citizen of Canada, but also a citizen of X, our ability to offer you consular services may be limited.</p>
            <h4>Useful links</h4><ul><li><a href="https://travel.gc.ca/travelling/dual">Travelling as a dual citizen</a></li></ul>
            """.trimIndent(),
        ).withoutCanadaSpecificAdvice()

        assertEquals(listOf("Drugs", "Dual citizenship"), sections.map { it.title })
        assertEquals(listOf(0, 1), sections.map { it.id })
        // The consular sentence and the gc.ca link go; the empty "Useful links" heading goes with them.
        assertEquals(listOf<Block>(Block.Paragraph(AdviceText("Dual citizenship is legally recognized in X."))), sections[1].blocks)
    }

    @Test
    fun emergencyNumbersBecomeTappableAndEmbassiesAreLeftOut() {
        val guide = DestinationGuide.from(
            AdvisoryStatus.Information(
                name = "Sweden", urlSlug = "sweden", friendlyDate = "October 14, 2026", advisoryText = "Exercise a high degree of caution",
                advisories = "<h3>Sweden - Exercise a high degree of caution</h3><p>Due to terrorism.</p>",
                entryExit = "<h3>Passport</h3><p>Canadian passport rules.</p><h3>Visas</h3><p>Not required.</p><h3>Children</h3><p>Learn about travelling with children.</p><h3>Health entry</h3><p>No vaccines needed.</p>",
                health = "", lawsCulture = "", disastersClimate = "",
                officesHtml = """<h3>Local services</h3><section><details><summary>Emergency services</summary><div><p>Dial 112 for emergency assistance or 1-800-555-0100 for tourists.</p></div></details></section><h3>Consular assistance</h3><p>Call 613 for the embassy.</p>""",
            ),
        )
        assertEquals(listOf("Health entry"), guide.entry.map { it.title })
        assertEquals("https://travel.gc.ca/destinations/sweden", guide.adviceUrl)
        val emergency = guide.emergency.single() as Block.Paragraph
        assertEquals(listOf(AdviceText.Link(5, 8, "tel:112")), emergency.text.links)
        assertTrue(emergency.hasPhoneLink)
    }
}
