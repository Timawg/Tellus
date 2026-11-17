package com.pathos.tellus.guide.events

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.LocalDate

class WikipediaEventsParserTest {

    private val wikitext = """
        Intro text.
        == Incumbents ==
        * 1 January – This is not in the events section and must be ignored entirely.
        == Events ==
        === January ===
        * 3 January – A bus collides with a lorry on the [[A1 motorway|motorway]] near the capital.<ref>{{cite news|title=x}}</ref>
        * January 9 {{snd}} US-style dates are read too, with a template as the separator here.
        * 6–22 February – [[Kenya at the 2026 Winter Olympics]]
        * 14 February
        ** The first of two events on the same day, listed as a sub-item below the date.
        ** The second event on that day, with '''bold''' and ''italic'' markup removed.
        * Ongoing – An undated topic that should be skipped because it has no date at all.
        * 20 February – Short.
        * 1 March – Heavy rain of {{convert|120|mm}} falls in the north, flooding several towns.
        * 25 December – A scheduled event later in the year that hasn't happened yet today.
        == Deaths ==
        * 2 January – Someone notable dies, which is outside the events section.
    """.trimIndent()

    private val events = WikipediaEventsParser.events(wikitext, year = 2026, today = LocalDate.of(2026, 11, 17))

    @Test
    fun readsDatedEventsNewestFirstWithinTheEventsSection() {
        assertEquals(
            listOf(
                LocalDate.of(2026, 3, 1),
                LocalDate.of(2026, 2, 14),
                LocalDate.of(2026, 2, 14),
                LocalDate.of(2026, 1, 9),
                LocalDate.of(2026, 1, 3),
            ),
            events.map { it.date },
        )
        assertEquals((0..4).toList(), events.map { it.id })
    }

    @Test
    fun cleansWikitext() {
        assertEquals("A bus collides with a lorry on the motorway near the capital.", events.last().text)
        assertEquals("US-style dates are read too, with a template as the separator here.", events[3].text)
        assertEquals("Heavy rain of 120 mm falls in the north, flooding several towns.", events[0].text)
        assertEquals("The second event on that day, with bold and italic markup removed.", events[2].text)
    }

    @Test
    fun keepsSameDaySubItemsInPageOrder() {
        assertEquals("The first of two events on the same day, listed as a sub-item below the date.", events[1].text)
    }

    @Test
    fun noEventsSectionMeansNoEvents() {
        assertNull(WikipediaEventsParser.eventsSection("== History ==\n* 1 January – Something"))
        assertEquals(emptyList<RecentEvent>(), WikipediaEventsParser.events("Plain text", 2026, LocalDate.of(2026, 1, 1)))
    }
}
