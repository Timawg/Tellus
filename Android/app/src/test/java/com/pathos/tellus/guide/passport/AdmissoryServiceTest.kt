package com.pathos.tellus.guide.passport

import com.pathos.tellus.countries.Country
import com.pathos.tellus.guide.TravelStatus
import com.pathos.tellus.guide.colors
import com.pathos.tellus.testing.FakeNetworkService
import com.pathos.tellus.ui.theme.StatusColors
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.io.IOException

class AdmissoryServiceTest {

    private val csv = "Passport,Destination,Requirement\nSE,TH,30\nSE,IN,e-visa\nSE,CN,visa required\nSE,SE,-1\nSE,KP,no admission\nSE,XX,visa on arrival\nbroken line\n"

    @Test
    fun mapsRequirementsToCategoriesAndColours() {
        val expected = mapOf(
            "30" to Triple("visa-free", "30", StatusColors.SECURE),
            "-1" to Triple("visa-free", "-1", StatusColors.SECURE),
            "e-visa" to Triple("e-visa", "", StatusColors.SEMISECURE),
            "visa on arrival" to Triple("visa on arrival", "", StatusColors.SEMISECURE),
            "visa required" to Triple("visa required", "", StatusColors.CAUTION),
            "no admission" to Triple("not admitted", "", StatusColors.DANGER),
            "something new" to Triple("something new", "", null),
        )
        expected.forEach { (requirement, result) ->
            val status = AdmissoryStatus.from("SE", "XX", requirement)
            assertEquals(requirement, result, Triple(status.category, status.duration, status.colors))
        }
    }

    @Test
    fun visaStatusTextMatchesIos() {
        val sweden = Country(name = Country.Name("Sweden"), translations = emptyMap(), latlng = emptyList())
        val status = TravelStatus.visa(AdmissoryStatus.from("SE", "TH", "30"), sweden)!!
        assertEquals("Visa · Sweden passport", status.title)
        assertEquals("Visa-Free · up to 30 days", status.value)
        assertEquals("Visa Required", TravelStatus.visa(AdmissoryStatus.from("SE", "CN", "visa required"), null)!!.value)
        assertNull(TravelStatus.visa(AdmissoryStatus.from("SE", "XX", "unknown"), null))
    }

    @Test
    fun downloadsTheDatasetOnceForConcurrentLookups() = runTest {
        val network = FakeNetworkService(mapOf("passport-index" to { csv }))
        val service = PassportIndexAdmissoryService(network)
        val statuses = listOf("TH", "IN", "CN").map { async { service.getAdmissoryStatus("SE", it) } }.awaitAll()

        assertEquals(listOf("visa-free", "e-visa", "visa required"), statuses.map { it.category })
        assertEquals(1, network.requests.size)
    }

    @Test(expected = IOException::class)
    fun unknownPairFails() = runTest {
        PassportIndexAdmissoryService(FakeNetworkService(mapOf("passport-index" to { csv }))).getAdmissoryStatus("SE", "ZZ")
    }
}
