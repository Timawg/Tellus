package com.pathos.tellus.hazards

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
import okhttp3.CacheControl
import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.Duration
import java.time.Instant

class DisasterAlertsTest {

    private val json = Json { ignoreUnknownKeys = true }

    private fun feature(type: String, id: Long, level: String, current: String, from: String, countries: List<String>, name: String? = null) = """
        {"type":"Feature","geometry":{"type":"Point","coordinates":[10,20]},"properties":{
          "eventtype":"$type","eventid":$id,"episodeid":1,${name?.let { "\"name\":\"$it\"," } ?: ""}
          "alertlevel":"$level","iscurrent":$current,"fromdate":"$from","todate":"2026-11-17T00:00:00",
          "affectedcountries":[${countries.joinToString(",") { "{\"iso2\":\"$it\",\"iso3\":\"XXX\"}" }}],
          "severitydata":{"severity":5,"severitytext":"Magnitude 6.5M"},
          "url":{"report":"https://www.gdacs.org/report.aspx?eventid=$id"}}}
    """.trimIndent()

    private val body = """{"type":"FeatureCollection","features":[
        ${feature("EQ", 1, "Orange", "\"true\"", "2026-11-10T00:00:00", listOf("jp"), "Earthquake in Japan")},
        ${feature("EQ", 1, "Red", "\"true\"", "2026-11-11T00:00:00", listOf("jp"), "Earthquake in Japan")},
        ${feature("DR", 2, "Orange", "true", "2026-05-21T00:00:00", listOf("KE", "ET"), "Drought in Kenya")},
        ${feature("TC", 3, "Orange", "\"false\"", "2026-11-01T00:00:00", listOf("PH"), "Cyclone over")},
        ${feature("FL", 4, "Green", "\"true\"", "2026-11-01T00:00:00", listOf("BD"))},
        ${feature("XX", 5, "Orange", "\"true\"", "not a date", listOf("BD"))}
    ]}"""

    @Test
    fun keepsCurrentOrangeAndRedAlertsLatestEpisodeRedFirst() {
        val alerts = json.decodeFromString<GdacsEventList>(body).currentAlerts

        // Red first, then by start; a missing start sorts earliest, like iOS's `distantPast`.
        assertEquals(listOf("EQ-1", "XX-5", "DR-2"), alerts.map { it.id })
        val quake = alerts[0]
        assertEquals(DisasterAlert.Level.RED, quake.level)
        assertEquals(Instant.parse("2026-11-11T00:00:00Z"), quake.start)
        assertEquals(setOf("JP"), quake.countryCodes)
        assertEquals("Magnitude 6.5M", quake.severity)
        // Unknown kinds and missing names fall back, and bad dates are just missing.
        assertEquals(DisasterAlert.Kind.OTHER to "Disaster", alerts[1].kind to alerts[1].name)
        assertEquals(null, alerts[1].start)
    }

    @Test
    fun serviceFiltersByCountryAndCachesForHalfAnHour() = runTest {
        val clock = MutableClock(Instant.parse("2026-11-17T12:00:00Z"))
        val network = FakeNetworkService(mapOf("gdacs" to { body }))
        val service = GdacsDisasterAlertService(network, json, clock)

        assertEquals(listOf("DR-2"), service.getAlerts("ke").map { it.id })
        assertEquals(emptyList<DisasterAlert>(), service.getAlerts("SE"))
        val url = network.requests.single().url
        assertEquals("Orange;Red", url.queryParameter("alertlevel"))
        assertEquals("2026-10-18", url.queryParameter("fromdate"))
        assertEquals("2026-11-17", url.queryParameter("todate"))
        assertEquals(CacheControl.FORCE_NETWORK.toString(), network.requests.single().cacheControl.toString())

        clock.now = clock.now.plus(Duration.ofMinutes(31))
        service.getAlerts("KE")
        assertEquals(2, network.requests.size)
    }

    private fun alert(kind: DisasterAlert.Kind, level: DisasterAlert.Level, name: String) =
        DisasterAlert("$kind-$name", kind, level, name, null, null, null, setOf("XX"), null)

    @Test
    fun disasterStatusFollowsWorstUrgentAlert() {
        val drought = alert(DisasterAlert.Kind.DROUGHT, DisasterAlert.Level.RED, "Drought")
        val flood = alert(DisasterAlert.Kind.FLOOD, DisasterAlert.Level.ORANGE, "Flood")
        val quake = alert(DisasterAlert.Kind.EARTHQUAKE, DisasterAlert.Level.RED, "Quake")
        fun status(vararg alerts: DisasterAlert) = TravelStatus.disasters(alerts.toList()).let { it.colors to it.value }

        assertEquals(StatusColors.SECURE to "No active alerts", status())
        assertEquals(StatusColors.SEMISECURE to "Drought", status(drought))
        assertEquals(StatusColors.CAUTION to "Orange alert: Flood", status(drought, flood))
        assertEquals(StatusColors.DANGER to "Red alert: Quake", status(flood, quake))
    }

    @Test
    fun cardAlertPutsUrgentDisastersFirstButNotDroughts() {
        val now = Instant.parse("2026-11-17T00:00:00Z")
        val outage = listOf(InternetOutage(now, now, isOngoing = true, signals = emptyList()))
        val withFlood = CountryGuideUiState(
            disasterAlerts = listOf(alert(DisasterAlert.Kind.FLOOD, DisasterAlert.Level.ORANGE, "Flood")),
            internetOutages = outage,
        )
        assertEquals("Flood" to GuideTopic.CLIMATE, CardAlert.from(withFlood, now)!!.let { it.title to it.topic })

        val withDrought = withFlood.copy(disasterAlerts = listOf(alert(DisasterAlert.Kind.DROUGHT, DisasterAlert.Level.ORANGE, "Drought")))
        assertEquals("Internet disruption detected", CardAlert.from(withDrought, now)?.title)
    }
}
