package com.pathos.tellus.guide.democracy

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.File

class DemocracyDatasetTest {

    private val dataset = Json.decodeFromString<DemocracyDataset>(
        """{"version":16,"countries":{
            "SWE":[{"year":2024,"value":0.9}],
            "PSE":[{"year":2024,"value":0.2}],
            "PSG":[{"year":2024,"value":0.1}],
            "XKX":[{"year":2024,"value":0.6}],
            "EMP":[]
        }}""",
    )

    @Test
    fun countryHasOneSeries() {
        val profile = dataset.profile("swe")
        assertEquals(16, profile.version)
        assertEquals(listOf("SWE"), profile.series.map { it.id })
    }

    @Test
    fun palestineSplitsIntoWestBankAndGaza() {
        assertEquals(listOf("West Bank", "Gaza"), dataset.profile("PSE").series.map { it.area })
    }

    @Test
    fun kosovoUsesVdemCode() {
        assertEquals(listOf("XKX"), dataset.profile("UNK").series.map { it.id })
    }

    @Test
    fun missingOrEmptyHasNoSeries() {
        assertEquals(emptyList<DemocracyProfile.Series>(), dataset.profile("EMP").series)
        assertEquals(emptyList<DemocracyProfile.Series>(), dataset.profile(null).series)
    }

    @Test
    fun bundledDatasetDecodes() {
        val file = File(System.getProperty("user.dir"), "../../iOS/Tellus/Features/CountryGuide/DemocracySafety/vdem-democracy.json")
        val real = Json.decodeFromString<DemocracyDataset>(file.readText())
        assertEquals(1, real.profile("SWE").series.size)
    }
}
