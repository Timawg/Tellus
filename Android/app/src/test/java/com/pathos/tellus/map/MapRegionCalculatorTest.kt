package com.pathos.tellus.map

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MapRegionCalculatorTest {

    private val portrait = 402.0 / 874.0

    private fun rect(west: Double, south: Double, east: Double, north: Double): MercatorRect {
        val topLeft = MercatorPoint.of(Coordinate(north, west))
        val bottomRight = MercatorPoint.of(Coordinate(south, east))
        return MercatorRect(topLeft.x, topLeft.y, bottomRight.x, bottomRight.y)
    }

    @Test
    fun countrySitsInTheMiddleOfTheFreeBand() {
        val country = rect(10.0, 40.0, 20.0, 50.0)
        val fit = MapRegionCalculator.fitting(country, portrait)
        val center = MercatorPoint.of(fit.center)
        // The band runs from 34% to 76% of the screen height, so its middle is 5% below the screen's.
        assertEquals(country.midY, center.y + 0.05 * fit.mercatorHeight, 1e-9)
        assertEquals(country.midX, center.x, 1e-9)
        // The country's height fills the band.
        assertTrue(fit.mercatorHeight >= country.height / 0.42 - 1e-12)
    }

    @Test
    fun tinyCountryKeepsMinimumWidth() {
        val vatican = rect(12.445, 41.90, 12.458, 41.907)
        val fit = MapRegionCalculator.fitting(vatican, portrait)
        val thirtyKm = 30_000 * MercatorPoint.perMetre(41.9)
        assertEquals(thirtyKm / portrait, fit.mercatorHeight, 1e-6)
    }

    @Test
    fun rectPastAntimeridianWrapsCentre() {
        val wrapped = MercatorRect(0.9, 0.2, 1.1, 0.3)
        val fit = MapRegionCalculator.fitting(wrapped, portrait)
        assertEquals(180.0, kotlin.math.abs(fit.center.longitude), 1e-6)
    }

    @Test
    fun viewNeverExceedsTheWorld() {
        val huge = MercatorRect(0.0, 0.0, 1.0, 1.0)
        val fit = MapRegionCalculator.fitting(huge, portrait)
        assertTrue(fit.mercatorHeight <= 1.0)
        assertEquals(0.5, MercatorPoint.of(fit.center).y, 1e-6)
    }

    @Test
    fun zoomShowsRequestedHeight() {
        assertEquals(0f, MapFit(Coordinate(0.0, 0.0), 1.0).zoom(256f), 1e-6f)
        assertEquals(3f, MapFit(Coordinate(0.0, 0.0), 0.25).zoom(512f), 1e-6f)
    }

    @Test
    fun areaFallbackNeedsAreaAndCentre() {
        assertNull(MapRegionCalculator.fitting(null, listOf(0.0, 0.0), portrait))
        assertNull(MapRegionCalculator.fitting(0.0, listOf(0.0, 0.0), portrait))
        assertNull(MapRegionCalculator.fitting(100.0, listOf(0.0), portrait))
        val fit = MapRegionCalculator.fitting(12_100.0, listOf(10.0, 20.0), portrait)!!
        assertEquals(Coordinate(10.0, 20.0), fit.center)
        // 1° of latitude tall and 2° wide; on a portrait screen the width decides.
        assertEquals(2.0 / 360 / portrait, fit.mercatorHeight, 1e-9)
    }

    @Test
    fun mercatorRoundTrips() {
        val coordinate = Coordinate(59.33, 18.07)
        val back = MercatorPoint.of(coordinate).coordinate
        assertEquals(coordinate.latitude, back.latitude, 1e-9)
        assertEquals(coordinate.longitude, back.longitude, 1e-9)
    }
}
