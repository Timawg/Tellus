package com.pathos.tellus.guide.outages

import com.pathos.tellus.testing.FakeNetworkService
import com.pathos.tellus.testing.MutableClock
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Duration
import java.time.Instant

class InternetOutageServiceTest {

    private val json = Json { ignoreUnknownKeys = true }
    private val now = Instant.parse("2026-11-17T12:00:00Z")

    private fun event(start: Long, duration: Long, source: String) = IodaEventList.Event(start.toDouble(), duration.toDouble(), source)

    @Test
    fun keepsOnlyPeriodsSeenByTwoSignalsNewestFirst() {
        val t = now.epochSecond
        val list = IodaEventList(
            listOf(
                // Corroborated and long over.
                event(t - 86_400, 3_600, "bgp"),
                event(t - 85_000, 600, "ping-slash24"),
                // A single-signal blip.
                event(t - 40_000, 300, "merit-nt"),
                // Corroborated and still going (ends within the last 30 minutes).
                event(t - 7_200, 7_000, "gtr"),
                event(t - 3_600, 3_500, "bgp"),
            ),
        )
        val outages = list.corroboratedOutages(until = now)

        assertEquals(2, outages.size)
        assertTrue(outages[0].isOngoing)
        assertEquals(listOf("Google traffic", "Routing (BGP)"), outages[0].signals)
        assertEquals(Instant.ofEpochSecond(t - 7_200), outages[0].start)
        assertEquals(false, outages[1].isOngoing)
        assertEquals(listOf("Active probing", "Routing (BGP)"), outages[1].signals)
        assertEquals(Instant.ofEpochSecond(t - 86_400 + 3_600), outages[1].end)
    }

    @Test
    fun requestsLastWeekAndCachesForFifteenMinutes() = runTest {
        val clock = MutableClock(now)
        val network = FakeNetworkService(mapOf("ioda" to { """{"data":[],"type":"events"}""" }))
        val service = IodaInternetOutageService(network, json, clock)

        service.getOutages("se")
        val url = network.requests.single().url
        assertEquals("SE", url.queryParameter("entityCode"))
        assertEquals((now.epochSecond - 7 * 86_400).toString(), url.queryParameter("from"))
        assertEquals(now.epochSecond.toString(), url.queryParameter("until"))

        clock.now = now.plus(Duration.ofMinutes(14))
        service.getOutages("SE")
        assertEquals(1, network.requests.size)
        clock.now = now.plus(Duration.ofMinutes(16))
        service.getOutages("SE")
        assertEquals(2, network.requests.size)
    }

    @Test
    fun invalidCodeSkipsTheNetwork() = runTest {
        val network = FakeNetworkService(emptyMap())
        assertEquals(emptyList<InternetOutage>(), IodaInternetOutageService(network, json, MutableClock(now)).getOutages("SWE"))
        assertTrue(network.requests.isEmpty())
    }
}
