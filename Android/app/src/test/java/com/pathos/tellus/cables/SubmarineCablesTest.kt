package com.pathos.tellus.cables

import com.pathos.tellus.map.Coordinate
import com.pathos.tellus.map.MercatorPoint
import com.pathos.tellus.map.MercatorRect
import com.pathos.tellus.map.tapTolerance
import com.pathos.tellus.testing.FakeNetworkService
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class SubmarineCablesTest {

    private val json = Json { ignoreUnknownKeys = true }

    @Test
    fun cablesMergeFeaturesByIdAndDropUnusableLines() {
        val cables = json.decodeFromString(CableGeoJson.serializer(), ROUTES).cables

        assertEquals(listOf("ak-link", "no-colour"), cables.map { it.id })
        val akLink = cables[0]
        assertEquals("#939597", akLink.colorHex)
        // Two features merge; the one-point line and the malformed pair are dropped.
        assertEquals(2, akLink.lines.size)
        assertEquals(Coordinate(46.8, -124.0), akLink.lines[0][0])
        assertEquals(listOf(Coordinate(50.0, -130.0), Coordinate(51.0, -131.0)), akLink.lines[1])
        // iOS's fallback grey when the feed leaves the colour out.
        assertEquals("#939597", cables[1].colorHex)
    }

    @Test
    fun landingPointsKeepOnlyPointFeatures() {
        val points = json.decodeFromString(CableGeoJson.serializer(), LANDING_POINTS).landingPoints

        assertEquals(listOf(CableLandingPoint("cork-ireland", "Cork, Ireland", Coordinate(51.9, -8.47))), points)
    }

    @Test
    fun sparseDetailsDecodeAndGroupByCountry() {
        val details = json.decodeFromString(CableDetails.serializer(), SPARSE_DETAILS)

        assertNull(details.length)
        assertNull(details.rfsYear)
        assertNull(details.isPlanned)
        assertEquals(
            listOf("Ireland" to listOf("Cork, Ireland"), "Other" to listOf("Somewhere")),
            details.landingPointsByCountry.map { (country, points) -> country to points.map { it.name } },
        )
        assertEquals("https://www.submarinecablemap.com/submarine-cable/ak-link", details.mapUrl)
    }

    @Test
    fun fullDetailsDecode() {
        val details = json.decodeFromString(CableDetails.serializer(), FULL_DETAILS)

        assertEquals("45,000 km", details.length)
        assertEquals(2024, details.rfsYear)
        assertEquals(true, details.isPlanned)
        assertEquals("Meta, MTN", details.owners)
        assertEquals("ASN", details.suppliers)
        assertEquals("https://2africacable.com", details.url)
    }

    @Test
    fun geometryFindsTheNearestCableWithinTolerance() {
        val tester = CableGeometry(
            listOf(
                SubmarineCable("north", "North", "#ffffff", listOf(listOf(Coordinate(10.0, -10.0), Coordinate(10.0, 10.0)))),
                SubmarineCable("south", "South", "#ffffff", listOf(listOf(Coordinate(-10.0, -10.0), Coordinate(-10.0, 10.0)))),
            ),
            emptyList(),
        )
        val tolerance = tapTolerance(22, 3f)

        assertEquals("north", tester.nearestCableId(MercatorPoint.of(Coordinate(10.1, 0.0)), tolerance))
        assertEquals("south", tester.nearestCableId(MercatorPoint.of(Coordinate(-9.9, 5.0)), tolerance))
        // Halfway between, far outside 22 dp at zoom 3.
        assertNull(tester.nearestCableId(MercatorPoint.of(Coordinate(0.0, 0.0)), tolerance))
        // Past the end of the route.
        assertNull(tester.nearestCableId(MercatorPoint.of(Coordinate(10.0, 20.0)), tolerance))
    }

    @Test
    fun geometryFindsTheNearestLandingPointWithinTolerance() {
        val cork = CableLandingPoint("cork", "Cork", Coordinate(51.9, -8.47))
        val bude = CableLandingPoint("bude", "Bude", Coordinate(50.83, -4.55))
        val geometry = CableGeometry(emptyList(), listOf(cork, bude))
        val tolerance = tapTolerance(12, 8f)

        assertEquals(cork, geometry.nearestLandingPoint(MercatorPoint.of(Coordinate(51.91, -8.46)), tolerance))
        assertNull(geometry.nearestLandingPoint(MercatorPoint.of(Coordinate(51.0, -6.5)), tolerance))
    }

    @Test
    fun crowdedLandingPointsAreThinnedForTiles() {
        val points = listOf(
            CableLandingPoint("a", "A", Coordinate(0.0, 0.0)),
            CableLandingPoint("b", "B", Coordinate(0.0, 0.01)),
            CableLandingPoint("c", "C", Coordinate(0.0, 5.0)),
            CableLandingPoint("far", "Far", Coordinate(60.0, 120.0)),
        )
        val geometry = CableGeometry(emptyList(), points)
        val world = MercatorRect(0.0, 0.0, 1.0, 1.0)

        // At zoom 3 an 8 dp dot spans about 0.55° of longitude: B hides behind A, C is clear.
        assertEquals(listOf("a", "c", "far"), visibleLandingPoints(geometry.points, world, tapTolerance(8, 3f)).map { it.landingPoint.id })
        // Zoomed in, all three near the equator show.
        assertEquals(listOf("a", "b", "c", "far"), visibleLandingPoints(geometry.points, world, tapTolerance(8, 14f)).map { it.landingPoint.id })
        // Points away from the tile are left out.
        val equatorTile = MercatorRect(0.49, 0.49, 0.52, 0.51)
        assertEquals(listOf("a", "b", "c"), visibleLandingPoints(geometry.points, equatorTile, tapTolerance(8, 14f)).map { it.landingPoint.id })
    }

    @Test
    fun tapToleranceIsConstantOnScreenAtEveryZoom() {
        assertEquals(22.0 / 256, tapTolerance(22, 0f), 1e-12)
        assertEquals(22.0 / (256 * 1024), tapTolerance(22, 10f), 1e-12)
    }

    @Test
    fun parsesHexColours() {
        assertEquals(0xFF939597.toInt(), parseHexColor("#939597"))
        assertEquals(0xFF00FF00.toInt(), parseHexColor("00ff00"))
        assertNull(parseHexColor("#fff"))
        assertNull(parseHexColor("#zzzzzz"))
    }

    @Test
    fun serviceLoadsTheDatasetOnceAndCachesDetails() = runTest {
        val network = FakeNetworkService(
            mapOf(
                "cable-geo.json" to { _ -> ROUTES },
                "landing-point-geo.json" to { _ -> LANDING_POINTS },
                "/cable/ak-link.json" to { _ -> SPARSE_DETAILS },
            ),
        )
        val service = SubmarineCableMapService(network, json, StandardTestDispatcher(testScheduler))

        val first = service.getCables()
        val second = service.getCables()
        service.getDetails("ak-link")
        service.getDetails("ak-link")

        assertEquals(first, second)
        assertEquals(2, first.cables.size)
        assertEquals(1, first.landingPoints.size)
        assertEquals(1, network.count("cable-geo.json"))
        assertEquals(1, network.count("landing-point-geo.json"))
        assertEquals(1, network.count("/cable/ak-link.json"))
        assertTrue(network.requests.all { it.url.toString().startsWith("https://www.submarinecablemap.com/api/v3/") })
    }

    @Test
    fun serviceRejectsIdsThatAreNotSlugs() = runTest {
        val network = FakeNetworkService(emptyMap())
        val service = SubmarineCableMapService(network, json, StandardTestDispatcher(testScheduler))

        for (id in listOf("", "../secrets", "a/b", "ålesund", "a b")) {
            try {
                service.getDetails(id)
                fail("Expected $id to be rejected")
            } catch (_: IllegalArgumentException) {
            }
        }
        assertTrue(network.requests.isEmpty())
    }

    private companion object {
        val ROUTES = """
            {"type":"FeatureCollection","features":[
              {"type":"Feature","properties":{"id":"ak-link","name":"AK-Link","color":"#939597","feature_id":"ak-link-0"},
               "geometry":{"type":"MultiLineString","coordinates":[[[-124.0,46.8],[-125.0,47.0]],[[-126.0,48.0]]]}},
              {"type":"Feature","properties":{"id":"ak-link","name":"AK-Link","color":"#939597","feature_id":"ak-link-1"},
               "geometry":{"type":"MultiLineString","coordinates":[[[-130.0,50.0],[-131.0,51.0],[1.0]]]}},
              {"type":"Feature","properties":{"id":"no-colour","name":"No colour"},
               "geometry":{"type":"MultiLineString","coordinates":[[[0.0,0.0],[1.0,1.0]]]}}
            ]}
        """.trimIndent()

        val LANDING_POINTS = """
            {"type":"FeatureCollection","features":[
              {"type":"Feature","properties":{"id":"cork-ireland","name":"Cork, Ireland","is_tbd":false},
               "geometry":{"type":"Point","coordinates":[-8.47,51.9]}},
              {"type":"Feature","properties":{"id":"bad","name":"Bad"},"geometry":{"type":"Point","coordinates":[1.0]}}
            ]}
        """.trimIndent()

        val SPARSE_DETAILS = """
            {"id":"ak-link","name":"AK-Link","length":null,"landing_points":[
              {"id":"cork-ireland","name":"Cork, Ireland","country":"Ireland","is_tbd":null},
              {"id":"somewhere","name":"Somewhere"}
            ]}
        """.trimIndent()

        val FULL_DETAILS = """
            {"id":"2africa","name":"2Africa","length":"45,000 km","owners":"Meta, MTN","suppliers":"ASN",
             "rfs_year":2024,"is_planned":true,"url":"https://2africacable.com","landing_points":[]}
        """.trimIndent()
    }
}
