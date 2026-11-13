package com.pathos.tellus.countries

import com.pathos.tellus.map.Coordinate
import com.pathos.tellus.map.MercatorPoint
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class CountryBordersTest {

    /** [lon, lat] ring for a box, closed like GeoJSON. */
    private fun box(west: Double, south: Double, east: Double, north: Double) =
        "[[$west,$south],[$east,$south],[$east,$north],[$west,$north],[$west,$south]]"

    private fun feature(code: String?, type: String, coordinates: String): String {
        val properties = code?.let { """{"cca3":"$it"}""" } ?: "{}"
        return """{"type":"Feature","properties":$properties,"geometry":{"type":"$type","coordinates":$coordinates}}"""
    }

    private val fixture = """
        {"type":"FeatureCollection","features":[
          ${feature("AAA", "MultiPolygon", "[[${box(0.0, 0.0, 10.0, 10.0)},${box(4.0, 4.0, 6.0, 6.0)}]]")},
          ${feature("BBB", "Polygon", "[${box(4.0, 4.0, 6.0, 6.0)}]")},
          ${feature("FRA", "MultiPolygon", "[[${box(20.0, 40.0, 25.0, 45.0)}],[${box(-50.0, 2.0, -49.0, 3.0)}]]")},
          ${feature("REU", "MultiPolygon", "[[${box(-50.0, 2.0, -49.0, 3.0)}]]")},
          ${feature("RUS", "MultiPolygon", "[[${box(30.0, 50.0, 180.0, 70.0)}],[${box(-180.0, 64.0, -170.0, 68.0)}]]")},
          ${feature(null, "Polygon", "[${box(100.0, -10.0, 101.0, -9.0)}]")},
          ${feature("PNT", "Point", "[1,1]")}
        ]}
    """.trimIndent()

    private val borders = CountryBorders.parse(fixture)

    @Test
    fun parseSkipsFeaturesWithoutCodeOrPolygons() {
        assertEquals(setOf("AAA", "BBB", "FRA", "REU", "RUS"), borders.keys)
        assertEquals(1, borders.getValue("AAA").polygons.single().holes.size)
    }

    @Test
    fun tapInsideCountryPicksIt() {
        assertEquals("AAA", CountryBorders.countryAt(Coordinate(2.0, 2.0), borders))
    }

    @Test
    fun tapInHolePicksEnclave() {
        assertEquals("BBB", CountryBorders.countryAt(Coordinate(5.0, 5.0), borders))
    }

    @Test
    fun tapOnSeaPicksNothing() {
        assertNull(CountryBorders.countryAt(Coordinate(-30.0, -30.0), borders))
    }

    @Test
    fun identicalPiecesPreferSmallerCountry() {
        assertEquals("REU", CountryBorders.countryAt(Coordinate(2.5, -49.5), borders))
    }

    @Test
    fun tapAcrossAntimeridianPicksCountry() {
        assertEquals("RUS", CountryBorders.countryAt(Coordinate(66.0, -175.0), borders))
    }

    @Test
    fun focusRectLeavesOutFarTerritories() {
        val focus = borders.getValue("FRA").focusRect
        val mainland = borders.getValue("FRA").polygons[0].bounds
        assertEquals(mainland, focus)
    }

    @Test
    fun focusRectShiftsPiecesAcrossAntimeridian() {
        val focus = borders.getValue("RUS").focusRect!!
        // The eastern piece joins the rest past the world's right edge.
        assertTrue("maxX ${focus.maxX}", focus.maxX > 1.0)
        assertEquals(MercatorPoint.of(Coordinate(0.0, 30.0)).x, focus.minX, 1e-9)
    }

    @Test
    fun bundledBordersMatchRealPlaces() {
        // The real dataset, read from where Gradle bundles it from.
        val file = File(System.getProperty("user.dir"), "../../iOS/Tellus/Features/Countries/Resources/country-borders.geojson")
        val real = CountryBorders.parse(file.readText())
        assertTrue(real.size > 200)
        assertEquals("SWE", CountryBorders.countryAt(Coordinate(57.78, 14.16), real)) // Jönköping; coasts are simplified
        assertEquals("LSO", CountryBorders.countryAt(Coordinate(-29.31, 27.48), real)) // Maseru, inside South Africa
        assertEquals("ZAF", CountryBorders.countryAt(Coordinate(-26.20, 28.05), real)) // Johannesburg
        assertEquals("RUS", CountryBorders.countryAt(Coordinate(65.0, -175.0), real)) // Chukotka
        assertNull(CountryBorders.countryAt(Coordinate(30.0, -40.0), real)) // mid-Atlantic
    }
}
