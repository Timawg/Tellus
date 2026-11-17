package com.pathos.tellus.guide.prices

import com.pathos.tellus.core.network.HttpError
import com.pathos.tellus.testing.FakeNetworkService
import com.pathos.tellus.testing.MutableClock
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Duration
import java.text.NumberFormat
import java.util.Locale

class EurostatPriceServiceTest {

    private val json = Json { ignoreUnknownKeys = true }
    private val clock = MutableClock()

    /** A 1×1×5×3×2 JSON-stat cube: categories × (EU, SE, EL) × (2023, 2024). */
    private val cube: String = run {
        val geo = listOf("EU27_2020", "SE", "EL")
        val values = mutableMapOf<Int, Double>()
        fun set(category: Int, area: Int, year: Int, value: Double) { values[category * 6 + area * 2 + year] = value }
        for (category in 0 until 5) for (year in 0..1) set(category, 0, year, 100.0)
        set(0, 1, 0, 118.0); set(0, 1, 1, 120.0); set(1, 1, 1, 110.0)
        set(0, 2, 0, 80.0); set(1, 2, 1, 90.0) // Greece has no overall price in 2024, so that year is skipped.
        val valueJson = values.entries.joinToString(",") { "\"${it.key}\":${it.value}" }
        """
        {"id":["freq","indic_ppp","ppp_cat18","geo","time"],"size":[1,1,5,3,2],
         "dimension":{
           "freq":{"category":{"index":{"A":0}}},
           "indic_ppp":{"category":{"index":{"PLI_EU27_2020":0}}},
           "ppp_cat18":{"category":{"index":{"E011":0,"A0101":1,"A0104":2,"A0107":3,"A0111":4}}},
           "geo":{"category":{"index":{${geo.withIndex().joinToString(",") { "\"${it.value}\":${it.index}" }}},
                              "label":{"SE":"Sweden","EL":"Greece"}}},
           "time":{"category":{"index":{"2023":0,"2024":1}}}},
         "value":{$valueJson},"status":{}}
        """.trimIndent()
    }

    private val levels = EurostatPriceLevels.parse(json, cube, clock.now)

    @Test
    fun comparesLatestSharedYear() {
        val comparison = levels.comparison("se", EurostatPriceLevels.EU_AVERAGE_CODE)!!
        assertEquals(2024, comparison.year)
        assertEquals(0.2, comparison.changes.getValue(EurostatPriceLevels.Category.OVERALL), 1e-9)
        assertEquals(0.1, comparison.changes.getValue(EurostatPriceLevels.Category.GROCERIES), 1e-9)
        assertFalse(EurostatPriceLevels.Category.HOUSING in comparison.changes)

        val withGreece = levels.comparison("SE", "EL")!!
        assertEquals(2023, withGreece.year)
        assertEquals(118.0 / 80 - 1, withGreece.changes.getValue(EurostatPriceLevels.Category.OVERALL), 1e-9)
    }

    @Test
    fun mapsIsoCodesToEurostatCodes() {
        assertEquals(2023, levels.comparison("GR", EurostatPriceLevels.EU_AVERAGE_CODE)!!.year)
        assertNull(levels.comparison("NO", EurostatPriceLevels.EU_AVERAGE_CODE))
    }

    @Test
    fun referenceAreasListEuAverageFirst() {
        assertEquals(listOf("EU average", "Greece"), levels.referenceAreas("SE").map { it.name })
    }

    @Test(expected = SerializationException::class)
    fun rejectsUnexpectedDimensions() {
        EurostatPriceLevels.parse(json, cube.replace("\"geo\",\"time\"", "\"geo\",\"year\""), clock.now)
    }

    @Test
    fun concurrentCallersShareOneDownloadAndDayOldDataRefreshes() = runTest {
        val network = FakeNetworkService(mapOf("eurostat" to { cube }))
        val service = EurostatPriceService(network, json, clock)
        (1..3).map { async { service.getPriceLevels() } }.awaitAll()
        assertEquals(1, network.requests.size)
        assertEquals(5, network.requests.single().url.queryParameterValues("ppp_cat18").size)

        clock.now = clock.now.plus(Duration.ofHours(25))
        service.getPriceLevels()
        assertEquals(2, network.requests.size)
    }

    @Test
    fun failedRefreshKeepsLastDataMarkedStale() = runTest {
        var fail = false
        val network = FakeNetworkService(mapOf("eurostat" to { if (fail) throw HttpError.InvalidStatus(500, ByteArray(0)) else cube }))
        val service = EurostatPriceService(network, json, clock)
        assertFalse(service.getPriceLevels().isStale)

        fail = true
        clock.now = clock.now.plus(Duration.ofHours(25))
        assertTrue(service.getPriceLevels().isStale)
    }

    @Test
    fun describesPriceDifferences() {
        val format = { NumberFormat.getPercentInstance(Locale.US) }
        assertEquals("12% higher", priceDifference(0.12, format()))
        assertEquals("3.5% lower", priceDifference(-0.035, format()))
        assertEquals("About the same", priceDifference(0.0004, format()))
    }
}
