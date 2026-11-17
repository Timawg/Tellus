package com.pathos.tellus.guide.advisories

import com.pathos.tellus.guide.GuideTopic
import org.junit.Assert.assertEquals
import org.junit.Test

class DestinationGuideTest {

    private val guide = DestinationGuide.from(
        AdvisoryStatus.Information(
            name = "X", urlSlug = "x", friendlyDate = "", advisoryText = "",
            advisories = "",
            entryExit = "<h3>Entry rules</h3><p>Show a return ticket.</p>",
            health = "<h3>Vaccines</h3><p>Measles vaccine recommended.</p>",
            lawsCulture = """
                <p>You must abide by local laws.</p>
                <h3>Drugs</h3><p>Penalties for drug offences are severe.</p>
                <h3>Dual citizenship</h3><p>Dual citizenship is not legally recognized in X.</p>
                <h3>International Child Abduction</h3><p>X is not a party to the Hague Convention.</p>
                <h3>Dress and behaviour</h3><p>Dress conservatively.</p>
            """.trimIndent(),
            disastersClimate = "<h3>Rainy season</h3><p>Flooding is common.</p>",
            officesHtml = "",
        ),
    )

    @Test
    fun lawsTopicSelectsLawsAdviceWithoutCanadaSpecificTopics() {
        val laws = guide.sections(GuideTopic.LAWS)
        assertEquals(listOf(null, "Drugs", "Dual citizenship", "Dress and behaviour"), laws.map { it.title })
        assertEquals(listOf(0, 1, 2, 3), laws.map { it.id })
    }

    @Test
    fun eachTopicSelectsItsOwnAdvice() {
        assertEquals(listOf("Entry rules"), guide.sections(GuideTopic.ENTRY).map { it.title })
        assertEquals(listOf("Vaccines"), guide.sections(GuideTopic.HEALTH).map { it.title })
        assertEquals(listOf("Rainy season"), guide.sections(GuideTopic.CLIMATE).map { it.title })
        assertEquals(emptyList<AdviceSection>(), guide.sections(GuideTopic.OVERVIEW))
    }
}
