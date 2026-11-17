package com.pathos.tellus.guide.electricity

import com.pathos.tellus.core.network.HttpError
import com.pathos.tellus.testing.FakeNetworkService
import com.pathos.tellus.testing.MutableClock
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestDispatcher
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.time.Duration

class EmberElectricityServiceTest {

    @get:Rule
    val folder = TemporaryFolder()

    private val json = Json { ignoreUnknownKeys = true }
    private val clock = MutableClock()

    private val csv = """
        ﻿Area,ISO 3 code,Year,Electricity source,Is aggregated source,Generation (TWh),Share of generation (%)
        Sweden,SWE,2023,Total generation,True,163.0,100
        Sweden,SWE,2024,Total generation,True,170.5,100
        Sweden,SWE,2024,Hydro,False,70.2,41.2
        Sweden,SWE,2024,Nuclear,False,49.0,28.7
        Sweden,SWE,2024,"Other, fossil",False,1.5,0.9
        Sweden,SWE,2024,Coal,False,0,0
        Sweden,SWE,2024,Clean,True,160,93.8
        Sweden,SWE,2024,Net imports,True,-30.1,
        Sweden,SWE,2025,Hydro,False,71,
        Kosovo,XKX,2024,Total generation,True,6.1,100
        ASEAN,,2024,Total generation,True,1300,100
        Broken,BRK,notayear,Total generation,True,1,100
    """.trimIndent()

    @Test
    fun parsesLatestYearWithTotalAndSortsFuels() {
        val profile = EmberElectricityDataset.profiles(csv).getValue("SWE")
        assertEquals(2024, profile.year)
        assertEquals(170.5, profile.totalGenerationTWh, 0.0)
        assertEquals(-30.1, profile.netImportsTWh!!, 0.0)
        // Aggregates and zero-generation fuels are left out; quoted names keep their comma.
        assertEquals(listOf("Hydro", "Nuclear", "Other, fossil"), profile.fuels.map { it.name })
        assertEquals(41.2, profile.fuels[0].sharePercent!!, 0.0)
    }

    private fun service(network: FakeNetworkService, dispatcher: TestDispatcher) =
        EmberElectricityService(network, json, clock, folder.root.resolve("ember.json"), dispatcher)

    @Test
    fun cachesOnDiskForAWeekAndMapsKosovo() = runTest {
        val network = FakeNetworkService(mapOf("ember" to { csv }))
        val dispatcher = StandardTestDispatcher(testScheduler)
        assertEquals(6.1, service(network, dispatcher).getProfile("unk")!!.totalGenerationTWh, 0.0)

        // A new instance (a new app launch) reads the disk cache.
        clock.now = clock.now.plus(Duration.ofDays(6))
        assertEquals(2024, service(network, dispatcher).getProfile("SWE")!!.year)
        assertEquals(1, network.requests.size)

        clock.now = clock.now.plus(Duration.ofDays(2))
        service(network, dispatcher).getProfile("SWE")
        assertEquals(2, network.requests.size)
    }

    @Test
    fun failedRefreshKeepsLastSnapshot() = runTest {
        var fail = false
        val network = FakeNetworkService(mapOf("ember" to { if (fail) throw HttpError.InvalidStatus(503, ByteArray(0)) else csv }))
        val service = service(network, StandardTestDispatcher(testScheduler))
        service.getProfile("SWE")

        fail = true
        clock.now = clock.now.plus(Duration.ofDays(8))
        assertEquals(2024, service.getProfile("SWE")!!.year)
    }

    @Test
    fun invalidCodeIsNoProfile() = runTest {
        val network = FakeNetworkService(emptyMap())
        assertNull(service(network, StandardTestDispatcher(testScheduler)).getProfile("SE"))
    }
}
