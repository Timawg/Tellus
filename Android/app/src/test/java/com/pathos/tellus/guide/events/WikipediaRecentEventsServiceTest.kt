package com.pathos.tellus.guide.events

import com.pathos.tellus.countries.Country
import com.pathos.tellus.testing.FakeNetworkService
import com.pathos.tellus.testing.MutableClock
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.Instant

class WikipediaRecentEventsServiceTest {

    private val json = Json { ignoreUnknownKeys = true }

    private val bahamas = Country(
        name = Country.Name("Bahamas", "Commonwealth of the Bahamas"), cca2 = "BS",
        translations = emptyMap(), latlng = emptyList(),
    )

    @Test
    fun candidateTitlesTryNamesWithAndWithoutThe() {
        assertEquals(
            listOf("2026 in Bahamas", "2026 in the Bahamas", "2026 in Commonwealth of the Bahamas", "2026 in the Commonwealth of the Bahamas"),
            WikipediaRecentEventsService.candidateTitles(bahamas, 2026),
        )
        val turkey = Country(name = Country.Name("Türkiye"), cca2 = "TR", translations = emptyMap(), latlng = emptyList())
        assertEquals("2026 in Turkey", WikipediaRecentEventsService.candidateTitles(turkey, 2026).first())
    }

    private fun response(content: String) = """
        {"query":{
          "normalized":[{"from":"2026 in the Bahamas","to":"2026 in the Bahamas"}],
          "redirects":[{"from":"2026 in the Bahamas","to":"2026 in The Bahamas"}],
          "pages":[
            {"title":"2026 in Bahamas","missing":true},
            {"title":"2026 in The Bahamas","revisions":[{"slots":{"main":{"content":${JsonPrimitive(content)}}}}]}
          ]}}
    """.trimIndent()

    @Test
    fun followsRedirectsAndIdentifiesItself() = runTest {
        val network = FakeNetworkService(
            mapOf("wikipedia" to { response("== Events ==\n* 5 March – A hurricane passes close to the islands without landfall.") }),
        )
        val clock = MutableClock(Instant.parse("2026-11-17T12:00:00Z"))
        val events = WikipediaRecentEventsService(network, json, clock).getRecentEvents(bahamas)!!

        assertEquals("2026 in The Bahamas", events.articleTitle)
        assertEquals(1, events.events.size)
        val request = network.requests.single()
        assertEquals(WikipediaRecentEventsService.USER_AGENT, request.header("User-Agent"))
        assertEquals(WikipediaRecentEventsService.USER_AGENT, request.header("Api-User-Agent"))
        // Only this year's titles after February.
        assertEquals(false, request.url.queryParameter("titles")!!.contains("2025"))
    }

    @Test
    fun earlyInTheYearAlsoAsksForLastYear() = runTest {
        val network = FakeNetworkService(mapOf("wikipedia" to { """{"query":{"pages":[]}}""" }))
        val clock = MutableClock(Instant.parse("2026-02-10T12:00:00Z"))
        assertNull(WikipediaRecentEventsService(network, json, clock).getRecentEvents(bahamas))
        assertEquals(true, network.requests.single().url.queryParameter("titles")!!.contains("2025 in Bahamas"))
    }
}
