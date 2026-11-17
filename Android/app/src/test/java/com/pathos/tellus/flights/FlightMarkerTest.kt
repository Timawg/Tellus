package com.pathos.tellus.flights

import com.pathos.tellus.map.Coordinate
import com.pathos.tellus.map.MercatorPoint
import com.pathos.tellus.map.MercatorRect
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class FlightMarkerTest {

    private fun marker(id: String, lat: Double, lon: Double) = FlightMarker(id, lat, lon, null, LiveFlight.Source.OPEN_SKY)

    private fun rect(west: Double, south: Double, east: Double, north: Double): MercatorRect {
        val topLeft = MercatorPoint.of(Coordinate(north, west))
        val bottomRight = MercatorPoint.of(Coordinate(south, east))
        return MercatorRect(topLeft.x, topLeft.y, bottomRight.x, bottomRight.y)
    }

    private val europe = rect(-10.0, 35.0, 30.0, 70.0)

    @Test
    fun keepsEveryVisibleFlightUnderTheLimit() {
        val markers = listOf(marker("a", 50.0, 8.0), marker("b", 60.0, 10.0), marker("outside", 0.0, 100.0))
        val sample = markers.distributed(europe, limit = 500)
        assertEquals(listOf("a", "b"), sample.markers.map { it.id })
        assertEquals(2, sample.visibleCount)
    }

    @Test
    fun samplesAcrossTheViewAndKeepsTheSelectedFlight() {
        // A dense cluster over Frankfurt and a few elsewhere.
        val dense = (0 until 900).map { marker("f%03d".format(it), 50.0 + (it % 30) * 0.001, 8.0 + (it / 30) * 0.001) }
        val spread = listOf(marker("oslo", 59.9, 10.7), marker("madrid", 40.4, -3.7), marker("athens", 37.9, 23.7))
        val sample = (dense + spread).distributed(europe, limit = 100, keeping = "f899")

        assertEquals(100, sample.markers.size)
        assertEquals(903, sample.visibleCount)
        assertTrue(sample.markers.map { it.id }.containsAll(listOf("oslo", "madrid", "athens", "f899")))
    }

    @Test
    fun wrapsAcrossTheDateLine() {
        val pacific = MercatorRect(MercatorPoint.of(Coordinate(0.0, 170.0)).x, 0.3, MercatorPoint.of(Coordinate(0.0, -170.0)).x + 1, 0.6)
        val sample = listOf(marker("east", 10.0, 175.0), marker("west", 10.0, -175.0), marker("far", 10.0, 0.0)).distributed(pacific, 500)
        assertEquals(setOf("east", "west"), sample.markers.map { it.id }.toSet())
    }
}
