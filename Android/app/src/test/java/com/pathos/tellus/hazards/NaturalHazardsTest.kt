package com.pathos.tellus.hazards

import com.pathos.tellus.core.network.HttpError
import com.pathos.tellus.map.Coordinate
import com.pathos.tellus.testing.FakeNetworkService
import com.pathos.tellus.testing.MutableClock
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException
import java.time.Instant
import java.time.ZoneOffset
import java.util.Locale

class NaturalHazardsTest {

    private val json = Json { ignoreUnknownKeys = true }

    private val usgs = """{"type":"FeatureCollection","features":[
        {"id":"us7000abcd","properties":{"mag":6.8,"place":"12 km SSW of Hualien City, Taiwan","time":1794921753000,"updated":1794921800000,"url":"https://earthquake.usgs.gov/x","tsunami":1,"alert":"yellow","type":"earthquake"},"geometry":{"type":"Point","coordinates":[121.5,23.9,10.2]}},
        {"id":"us2","properties":{"mag":5.6,"type":"earthquake"},"geometry":{"coordinates":[10,20,5]}},
        {"id":"us3","properties":{"mag":4.6,"alert":"orange"},"geometry":{"coordinates":[10,20]}},
        {"id":"us4","properties":{"mag":4.7,"type":"quarry blast"},"geometry":{"coordinates":[10,20]}},
        {"id":"us5","properties":{"mag":null},"geometry":{"coordinates":[10,20]}},
        {"id":"us6","properties":{"mag":5.0},"geometry":{"coordinates":[200,20]}}
    ]}"""

    @Test
    fun readsUsgsEarthquakesWithSeverity() {
        val hazards = json.decodeFromString<UsgsEarthquakeFeed>(usgs).hazards
        assertEquals(listOf("usgs-us7000abcd", "usgs-us2", "usgs-us3"), hazards.map { it.id })
        val taiwan = hazards[0]
        assertEquals(NaturalHazard.Severity.SEVERE, taiwan.severity)
        assertEquals(Coordinate(23.9, 121.5), taiwan.coordinate)
        assertEquals(10.2, taiwan.depth!!, 0.0)
        assertTrue(taiwan.mayCauseTsunami)
        assertEquals("Yellow", taiwan.alertLevel)
        assertEquals(Instant.ofEpochMilli(1794921753000), taiwan.date)
        assertEquals(NaturalHazard.Severity.MODERATE, hazards[1].severity)
        // A PAGER orange makes even a small quake severe.
        assertEquals(NaturalHazard.Severity.SEVERE, hazards[2].severity)
    }

    private fun gdacsFeature(type: String, id: Long, episode: Long, level: String, current: String = "\"true\"", severity: String? = null, lon: Double = 130.0) = """
        {"type":"Feature","geometry":{"type":"Point","coordinates":[$lon,15.0]},"properties":{
          "eventtype":"$type","eventid":$id,"episodeid":$episode,"name":"$type $id","country":"Somewhere","alertlevel":"$level","iscurrent":$current,
          "fromdate":"2026-11-10T00:00:00","todate":"2026-11-16T06:00:00",
          "affectedcountries":[{"iso2":"PH","countryname":"Philippines"},{"iso2":"JP","countryname":"Japan"}],
          ${severity?.let { "\"severitydata\":{\"severitytext\":\"$it\"}," } ?: ""}
          "url":{"report":"https://www.gdacs.org/report.aspx?eventid=$id"}}}
    """.trimIndent()

    @Test
    fun readsGdacsEventsAtTheirLatestEpisode() {
        val list = json.decodeFromString<GdacsEventList>("""{"features":[
            ${gdacsFeature("TC", 1, 3, "Orange", severity = "Hurricane/Typhoon > 74 mph (maximum wind speed of 157 km/h)")},
            ${gdacsFeature("TC", 1, 2, "Green")},
            ${gdacsFeature("EQ", 2, 1, "Red")},
            ${gdacsFeature("FL", 3, 1, "Green", severity = "Magnitude 0")},
            ${gdacsFeature("WF", 4, 1, "Red", current = "\"false\"")}
        ]}""")
        val hazards = list.hazards.associateBy { it.id }

        assertEquals(setOf("gdacs-TC-1", "gdacs-FL-3"), hazards.keys)
        val cyclone = hazards.getValue("gdacs-TC-1")
        assertEquals(NaturalHazard.Severity.MODERATE, cyclone.severity)
        assertEquals("Up to 157 km/h", cyclone.summary)
        assertEquals("Philippines, Japan", cyclone.place)
        assertEquals(1L to 3L, cyclone.gdacsEpisode)
        assertEquals(Instant.parse("2026-11-16T06:00:00Z"), cyclone.updated)
        assertNull(hazards.getValue("gdacs-FL-3").summary)
    }

    @Test
    fun tidiesGdacsSeverityText() {
        assertEquals("6,306 ha burned", gdacsSummary("Green impact for forestfire in 6306 ha", DisasterAlert.Kind.WILDFIRE, Locale.US))
        assertEquals("Medium impact", gdacsSummary(" Medium impact ", DisasterAlert.Kind.DROUGHT))
        assertNull(gdacsSummary("  ", DisasterAlert.Kind.DROUGHT))
    }

    @Test
    fun readsCycloneTrackSegments() {
        val geometry = json.decodeFromString<GdacsEventGeometry>("""{"features":[
            {"geometry":{"type":"LineString","coordinates":[[130,15],[131,16]]},"properties":{"Class":"Line_Line_0","forecast":false}},
            {"geometry":{"type":"LineString","coordinates":[[131,16],[132,17]]},"properties":{"Class":"Line_Line_1","forecast":true}},
            {"geometry":{"type":"Polygon","coordinates":[[[1,1],[2,2],[3,3]]]},"properties":{"Class":"Poly_Cones"}},
            {"geometry":{"type":"LineString","coordinates":[[130,15]]},"properties":{"Class":"Line_Line_2"}}
        ]}""")
        val hazard = json.decodeFromString<GdacsEventList>("""{"features":[${gdacsFeature("TC", 1, 3, "Red")}]}""").hazards.single()
        val track = geometry.track(hazard)!!
        assertEquals(listOf(listOf(Coordinate(15.0, 130.0), Coordinate(16.0, 131.0))), track.observed)
        assertEquals(1, track.forecast.size)
        assertEquals(NaturalHazard.Severity.SEVERE, track.severity)
    }

    private val eruptions = """{"features":[
        {"properties":{"VolcanoNumber":351020,"VolcanoName":"Ruiz, Nevado del","ExplosivityIndexMax":2,"StartDate":"20141118","LatitudeDecimal":4.892,"LongitudeDecimal":-75.324}},
        {"properties":{"VolcanoNumber":351020,"VolcanoName":"Ruiz, Nevado del","ExplosivityIndexMax":3,"StartDate":"19850911","LatitudeDecimal":4.892,"LongitudeDecimal":-75.324}},
        {"properties":{"VolcanoNumber":261080,"VolcanoName":"Semeru","ExplosivityIndexMax":4,"StartDate":"20141101","LatitudeDecimal":-8.108,"LongitudeDecimal":112.922}}
    ]}"""

    @Test
    fun readsSmithsonianEruptionsOnePerVolcano() {
        val hazards = json.decodeFromString<GvpEruptionFeed>(eruptions).hazards.associateBy { it.id }
        val ruiz = hazards.getValue("gvp-351020")
        assertEquals("Nevado del Ruiz", ruiz.name)
        assertEquals(2, ruiz.explosivity)
        assertEquals(Instant.parse("2014-11-18T00:00:00Z"), ruiz.date)
        assertEquals(NaturalHazard.Severity.MODERATE, ruiz.severity)
        assertEquals(NaturalHazard.Severity.SEVERE, hazards.getValue("gvp-261080").severity)
    }

    @Test
    fun serviceUsesWhicheverSourcesAnswerAndDropsDuplicateVolcanoes() = runTest {
        val gdacsVolcano = gdacsFeature("VO", 9, 1, "Orange", lon = 112.9).replace("15.0]", "-8.2]")
        val network = FakeNetworkService(
            mapOf(
                "earthquake.usgs.gov" to { throw HttpError.InvalidStatus(503, ByteArray(0)) },
                "eventlist=TC" to { """{"features":[${gdacsFeature("TC", 1, 3, "Orange")}, $gdacsVolcano]}""" },
                // GDACS answers an empty search with 204 and no body.
                "eventlist=WF" to { "" },
                "volcano.si.edu" to { eruptions },
                "getgeometry" to { """{"features":[{"geometry":{"type":"LineString","coordinates":[[130,15],[131,16]]},"properties":{"Class":"Line_Line_0"}}]}""" },
            ),
        )
        val service = LiveHazardService(network, json, MutableClock(Instant.parse("2026-11-17T12:00:00Z")))
        val hazards = service.getHazards()

        assertEquals(setOf("gvp-351020", "gvp-261080", "gdacs-TC-1"), hazards.map { it.id }.toSet())
        val cyclone = hazards.first { it.id == "gdacs-TC-1" }
        service.getTrack(cyclone)
        assertTrue(service.getTrack(cyclone) != null)
        assertEquals(1, network.count("getgeometry"))
        assertEquals("TC;FL;VO", network.requests.first { it.url.toString().contains("eventlist=TC") }.url.queryParameter("eventlist"))
    }

    @Test(expected = IOException::class)
    fun failsWhenNoMainSourceAnswers() = runTest {
        val network = FakeNetworkService(mapOf("" to { throw HttpError.InvalidStatus(500, ByteArray(0)) }))
        LiveHazardService(network, json, MutableClock()).getHazards()
    }

    @Test
    fun formatsDetailsLikeIos() {
        assertEquals("48.86° N, 2.35° E", coordinateText(Coordinate(48.8566, 2.3522), Locale.US))
        assertEquals("33.87° S, 151.21° W", coordinateText(Coordinate(-33.8688, -151.2093), Locale.US))
        assertEquals("Orange · significant", impactText("orange"))
        val now = Instant.parse("2026-11-17T00:00:00Z")
        assertEquals("1985", eruptionStart(Instant.parse("1985-09-11T00:00:00Z"), now, ZoneOffset.UTC))
    }
}
