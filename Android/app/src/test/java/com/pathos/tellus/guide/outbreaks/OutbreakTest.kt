package com.pathos.tellus.guide.outbreaks

import com.pathos.tellus.countries.Country
import com.pathos.tellus.guide.CardAlert
import com.pathos.tellus.guide.CountryGuideUiState
import com.pathos.tellus.guide.GuideTopic
import com.pathos.tellus.guide.TravelStatus
import com.pathos.tellus.guide.outages.InternetOutage
import com.pathos.tellus.testing.FakeNetworkService
import com.pathos.tellus.testing.MutableClock
import com.pathos.tellus.ui.theme.StatusColors
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Duration
import java.time.Instant

class OutbreakTest {

    @Test
    fun splitsTitlesAtTheRightSeparator() {
        val cases = mapOf(
            "Nipah virus disease - India" to ("Nipah virus disease" to "India"),
            "Avian Influenza A(H5N1)- Cambodia" to ("Avian Influenza A(H5N1)" to "Cambodia"),
            "Avian Influenza A(H5N2)-Mexico" to ("Avian Influenza A(H5N2)" to "Mexico"),
            "Marburg virus disease– United Republic of Tanzania" to ("Marburg virus disease" to "United Republic of Tanzania"),
            "Cholera - Guinea-Bissau" to ("Cholera" to "Guinea-Bissau"),
            "Ebola disease caused by Bundibugyo virus, Democratic Republic of the Congo & Uganda" to
                ("Ebola disease caused by Bundibugyo virus" to "Democratic Republic of the Congo & Uganda"),
            "Multi-country outbreak of mpox" to ("Multi-country outbreak of mpox" to ""),
        )
        cases.forEach { (title, expected) -> assertEquals(title, expected, WhoOutbreakList.split(title)) }
    }

    @Test
    fun summaryKeepsTwoSentencesWithoutMarkup() {
        assertEquals(
            "On 29 October the IHR Focal Point notified WHO. The case is a man aged 60.",
            WhoOutbreakList.shortSummary("<p>On 29 October the IHR   Focal Point notified WHO. The case is a man aged 60. He is recovering.</p>"),
        )
        assertEquals(298, WhoOutbreakList.shortSummary("x".repeat(400)).length)
    }

    private fun country(code: String, common: String, official: String = common, alt: List<String> = emptyList()) =
        Country(name = Country.Name(common, official), cca2 = code, altSpellings = alt, translations = emptyMap(), latlng = emptyList())

    private val countries = listOf(
        country("CD", "DR Congo", "Democratic Republic of the Congo"),
        country("CG", "Republic of the Congo", alt = listOf("Congo")),
        country("GN", "Guinea"),
        country("GW", "Guinea-Bissau"),
        country("VN", "Vietnam", "Socialist Republic of Vietnam"),
        country("KE", "Kenya", alt = listOf("KE")),
    )

    private fun report(disease: String, places: String, daysAgo: Long) =
        OutbreakReport("$disease$places$daysAgo", disease, places, Instant.parse("2026-11-17T00:00:00Z").minus(Duration.ofDays(daysAgo)), "", null)

    @Test
    fun matchesLongestNamesFirstAndKeepsNewestPerDisease() {
        val index = OutbreakCountryMatcher.index(
            listOf(
                report("Ebola", "Democratic Republic of the Congo, Kenya", daysAgo = 10),
                report("Ebola", "Democratic Republic of the Congo", daysAgo = 40),
                report("Cholera", "Guinea-Bissau", daysAgo = 5),
                report("Dengue", "Viet Nam", daysAgo = 3),
            ),
            countries,
        )
        assertEquals(listOf(10L), index.getValue("CD").map { Duration.between(it.published, Instant.parse("2026-11-17T00:00:00Z")).toDays() })
        assertEquals(setOf("CD", "KE", "GW", "VN"), index.keys)
        assertNull(index["CG"])
        assertNull(index["GN"])
    }

    @Test
    fun indexesTheRealCountryListQuickly() {
        val many = (1..250).map { country("C$it", "Country number $it", "Republic of Country $it", alt = listOf("Land $it")) } +
            country("QA", "Qatar", "State of Qatar")
        val reports = (1..100).map { report("Disease $it", "Qatar, Country number ${it % 250}, Land ${it % 7}", it.toLong()) }
        val started = System.nanoTime()
        val index = OutbreakCountryMatcher.index(reports, many)
        val elapsedMs = (System.nanoTime() - started) / 1_000_000
        assertEquals(100, index.getValue("QA").size)
        assertTrue("Indexing took $elapsedMs ms", elapsedMs < 1_000)
    }

    @Test
    fun healthStatusDependsOnReportAge() {
        val now = Instant.parse("2026-11-17T00:00:00Z")
        val day = { _: Instant -> "1 Nov" }
        assertEquals(StatusColors.SECURE to "No WHO outbreak reports", TravelStatus.health(emptyList(), now, day).let { it.colors to it.value })
        assertEquals(StatusColors.CAUTION to "Ebola, reported 1 Nov", TravelStatus.health(listOf(report("Ebola", "", 30)), now, day).let { it.colors to it.value })
        assertEquals(StatusColors.SEMISECURE, TravelStatus.health(listOf(report("Ebola", "", 31)), now, day).colors)
        assertEquals("No WHO reports in the last six months", TravelStatus.health(listOf(report("Ebola", "", 181)), now, day).value)
    }

    @Test
    fun cardAlertPrefersOutagesThenRecentOutbreaks() {
        val now = Instant.parse("2026-11-17T00:00:00Z")
        val recent = CountryGuideUiState(outbreakReports = listOf(report("Ebola", "", 5)))
        assertEquals(GuideTopic.HEALTH, CardAlert.from(recent, now)?.topic)
        assertEquals("Outbreak: Ebola", CardAlert.from(recent, now)?.title)
        assertNull(CardAlert.from(CountryGuideUiState(outbreakReports = listOf(report("Ebola", "", 31))), now))

        val outage = recent.copy(internetOutages = listOf(InternetOutage(now, now, isOngoing = true, signals = emptyList())))
        assertEquals("Internet disruption detected", CardAlert.from(outage, now)?.title)
    }

    @Test
    fun serviceSkipsBadDatesAndCachesForAnHour() = runTest {
        val body = """{"value":[
            {"Title":"MERS – Qatar","PublicationDate":"2026-11-13T13:48:47Z","UrlName":"2026-DON626","Summary":"Qatar notified WHO."},
            {"Title":"Bad – Date","PublicationDate":"yesterday"}]}"""
        val clock = MutableClock()
        val network = FakeNetworkService(mapOf("who.int" to { body }))
        val service = WhoOutbreakService(network, Json { ignoreUnknownKeys = true }, clock)

        val reports = service.getReports()
        assertEquals(listOf("MERS"), reports.map { it.disease })
        assertEquals("https://www.who.int/emergencies/disease-outbreak-news/item/2026-DON626", reports.single().url)
        assertEquals("100", network.requests.single().url.queryParameter("\$top"))

        clock.now = clock.now.plus(Duration.ofMinutes(59))
        service.getReports()
        assertEquals(1, network.requests.size)
        clock.now = clock.now.plus(Duration.ofMinutes(2))
        service.getReports()
        assertEquals(2, network.requests.size)
    }
}
