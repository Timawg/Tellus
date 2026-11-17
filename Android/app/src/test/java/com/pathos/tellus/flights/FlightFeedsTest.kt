package com.pathos.tellus.flights

import com.pathos.tellus.core.network.HttpError
import com.pathos.tellus.map.Coordinate
import com.pathos.tellus.testing.FakeNetworkService
import com.pathos.tellus.testing.MutableClock
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.time.Instant

class FlightFeedsTest {

    private val json = Json { ignoreUnknownKeys = true }

    @Test
    fun parsesOpenSkyStateVectors() {
        val text = """{"time":1794921753,"states":[
            ["4ACB58","SAS1466 ","Sweden",1794921752,1794921753,12.3565,55.8119,5448.3,false,169.75,351.11,16.58,null,5219.7,"1223",false,0],
            ["4bc8e2","        ","Turkey",1794921748,1794921748,12.6492,55.6265,null,true,1.03,101.25,null,null,null,null,false,0,3],
            ["000001",null,"Nowhere",null,1794921748,null,null,null,false,null,null,null,null,null,null,false,0]
        ]}"""
        val flights = OpenSkyStates.parse(json, text)

        assertEquals(listOf("4acb58", "4bc8e2"), flights.map { it.id })
        val sas = flights[0]
        assertEquals("SAS1466", sas.callsign)
        assertEquals(Coordinate(55.8119, 12.3565), sas.coordinate)
        // Geometric altitude is preferred over barometric.
        assertEquals(5219.7, sas.altitudeMeters!!, 1e-9)
        assertEquals(351.11, sas.track!!, 1e-9)
        assertEquals("1223", sas.squawk)
        assertEquals(Instant.ofEpochSecond(1794921753), sas.lastContact)
        assertNull(flights[1].callsign)
        assertTrue(flights[1].isOnGround)
        assertEquals(emptyList<LiveFlight>(), OpenSkyStates.parse(json, """{"time":1,"states":null}"""))
    }

    @Test
    fun parsesAdsbLolMilitaryAndFiltersNonAircraft() {
        val text = """{"now":1794921753000,"ac":[
            {"hex":"AE1FFC","flight":"RCH123  ","r":"05-5140","t":"C17","alt_baro":30000,"alt_geom":30500,"gs":450,"track":90,"baro_rate":-1200,"squawk":"7700","emergency":"general","category":"A5","lat":50.0,"lon":8.0,"seen_pos":2},
            {"hex":"ae2000","alt_baro":"ground","t":"H60","lat":51.0,"lon":9.0,"emergency":"none"},
            {"hex":"ae3000","t":"TWR","lat":51.0,"lon":9.0},
            {"hex":"ae4000","category":"C1","lat":51.0,"lon":9.0},
            {"hex":"ae5000","lat":51.0,"lon":9.0,"seen_pos":61},
            {"hex":"ae6000"}
        ]}"""
        val flights = AdsbLolAircraftList.parse(json, text, Instant.EPOCH)

        assertEquals(listOf("ae1ffc", "ae2000"), flights.map { it.id })
        val c17 = flights[0]
        assertEquals("RCH123", c17.callsign)
        assertEquals(30500 * 0.3048, c17.altitudeMeters!!, 1e-6)
        assertEquals(450 * 0.514444, c17.speedMetersPerSecond!!, 1e-6)
        assertEquals(-1200 * 0.3048 / 60, c17.verticalRateMetersPerSecond!!, 1e-6)
        assertEquals("general", c17.emergency)
        assertEquals(Instant.ofEpochMilli(1794921753000 - 2000), c17.lastContact)
        assertTrue(c17.isMilitary)
        val helicopter = flights[1]
        assertTrue(helicopter.isOnGround)
        assertNull(helicopter.altitudeMeters)
        assertNull(helicopter.emergency)
    }

    private fun flight(id: String, source: LiveFlight.Source = LiveFlight.Source.OPEN_SKY, lat: Double = 50.0) = LiveFlight(
        id, null, Coordinate(lat, 8.0), null, null, false, null, null, null, null, null, null, null, Instant.EPOCH, source,
    )

    @Test
    fun militaryReplacesOpenSkyAndAddsUnlisted() {
        val merged = listOf(flight("a"), flight("b")).merging(
            listOf(flight("b", LiveFlight.Source.ADSB_LOL_MILITARY), flight("c", LiveFlight.Source.ADSB_LOL_MILITARY)),
        )
        assertEquals(listOf("a" to false, "b" to true, "c" to true), merged.map { it.id to it.isMilitary })
    }

    @Test
    fun backoffHonoursRetryAfterOtherwiseDoublesUpToFifteenMinutes() {
        val backoff = RateLimitBackoff()
        val now = Instant.parse("2026-11-17T12:00:00Z")
        backoff.recordRateLimit(120.0, now)
        assertEquals(120.0, backoff.remainingDelay(now)!!, 1e-9)
        backoff.reset()
        val waits = (1..7).map { backoff.recordRateLimit(null, now); backoff.remainingDelay(now)!! }
        assertEquals(listOf(30.0, 60.0, 120.0, 240.0, 480.0, 900.0, 900.0), waits)
        assertNull(backoff.remainingDelay(now.plusSeconds(900)))
    }

    @Test
    fun rateLimitedOpenSkySkipsTheNetworkUntilTheWaitIsOver() = runTest {
        val clock = MutableClock(Instant.parse("2026-11-17T12:00:00Z"))
        var limited = true
        val network = FakeNetworkService(
            mapOf(
                "opensky" to { if (limited) throw HttpError.RateLimited(null) else """{"time":1,"states":[]}""" },
                "adsb.lol" to { """{"ac":[]}""" },
            ),
        )
        val service = OpenSkyFlightService(network, json, clock)

        repeat(2) {
            try {
                service.getFlights(CoordinateSpan(50.0, 51.0), CoordinateSpan(8.0, 9.0))
                fail("Expected a rate limit")
            } catch (error: HttpError.RateLimited) {
                assertEquals(30.0, error.retryAfterSeconds!!, 1e-9)
            }
        }
        assertEquals(1, network.count("opensky"))
        assertEquals("50.0", network.requests.single().url.queryParameter("lamin"))
        // adsb.lol is unaffected, and kept for 30 seconds.
        service.getMilitaryFlights()
        clock.now = clock.now.plusSeconds(29)
        service.getMilitaryFlights()
        assertEquals(1, network.count("adsb.lol"))

        limited = false
        clock.now = clock.now.plusSeconds(2)
        assertEquals(emptyList<LiveFlight>(), service.getFlights(null, null))
        assertEquals(2, network.count("opensky"))
    }

    @Test
    fun detailsAreCachedAndUnknownIsRemembered() = runTest {
        var routeCalls = 0
        val network = FakeNetworkService(
            mapOf(
                "aircraft/" to { throw HttpError.InvalidStatus(404, ByteArray(0)) },
                "callsign/" to {
                    routeCalls++
                    """{"response":{"flightroute":{"callsign":"SAS1466","callsign_iata":"SK1466",
                        "airline":{"name":"SAS","iata":"SK","icao":"SAS"},
                        "origin":{"name":"Copenhagen","municipality":"Copenhagen","iata_code":"CPH","icao_code":"EKCH","latitude":55.618,"longitude":12.656},
                        "destination":{"name":"Oslo","iata_code":"OSL","icao_code":"ENGM","latitude":60.194,"longitude":11.100}}}}"""
                },
            ),
        )
        val service = AdsbdbFlightDetailsService(network, json)

        assertNull(service.getAircraft("4ACB58"))
        assertNull(service.getAircraft("4acb58"))
        assertEquals(1, network.count("aircraft/"))
        assertNull(service.getAircraft("../x"))

        val route = service.getRoute(" sas1466 ")!!
        service.getRoute("SAS1466")
        assertEquals(1, routeCalls)
        assertEquals("CPH" to "OSL", route.origin.code to route.destination.code)
        // Between the two airports, and far off to the side.
        assertTrue(route.isPlausible(Coordinate(57.0, 12.0)))
        assertEquals(false, route.isPlausible(Coordinate(40.0, -3.0)))
        val (flown, remaining, fraction) = route.progress(Coordinate(57.0, 12.0))
        assertTrue(flown > 0 && remaining > 0 && fraction in 0.0..1.0)
    }

    @Test
    fun greatCircleRunsBetweenItsEnds() {
        val points = Geo.greatCircle(Coordinate(55.618, 12.656), Coordinate(40.64, -73.78), 8)
        assertEquals(9, points.size)
        assertEquals(55.618, points.first().latitude, 1e-9)
        assertEquals(-73.78, points.last().longitude, 1e-9)
        // Copenhagen to New York arcs north of both ends.
        assertTrue(points[4].latitude > 55.618)
        assertEquals(6_184_000.0, Geo.distance(Coordinate(55.618, 12.656), Coordinate(40.64, -73.78)), 20_000.0)
    }

    @Test
    fun formatsLiveValuesLikeIos() {
        assertEquals("178° S", headingText(178.4))
        assertEquals("360° N", headingText(359.9))
        assertEquals("Level", verticalRateText(0.3))
        assertTrue(verticalRateText(5.0).startsWith("Climbing"))
        assertTrue(altitudeText(10_000.0).endsWith(" m"))
    }
}
