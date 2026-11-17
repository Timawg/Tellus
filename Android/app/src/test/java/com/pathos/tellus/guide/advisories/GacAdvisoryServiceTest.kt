package com.pathos.tellus.guide.advisories

import com.pathos.tellus.testing.FakeNetworkService
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class GacAdvisoryServiceTest {

    private val json = Json { ignoreUnknownKeys = true }

    @Test
    fun decodesAdvisoryAndRevalidates() = runTest {
        val body = """
            {"metadata":{"generated":{"timestamp":1,"date":"x"}},
             "data":{"country-iso":"SE","advisory-state":1,"has-advisory-warning":0,"update-metadata":"",
               "eng":{"name":"Sweden","url-slug":"sweden","geo-group":"Europe","flag":null,"friendly-date":"October 14, 2026",
                 "advisory-text":"Exercise a high degree of caution","recent-updates":"","advisories":"<p>a</p>","security":"",
                 "entry-exit":"","health":"","laws-culture":"","disasters-climate":"","offices-help-abroad":null,
                 "offices-html":"","offices":[]},
               "fra":{}}}
        """.trimIndent()
        val network = FakeNetworkService(mapOf("travel-voyage" to { body }))
        val status = GacAdvisoryService(network, json).getAdvisoryStatus("SE")

        assertEquals(AdvisoryStatus.State.CAUTION, status.data.state)
        assertEquals("https://data.international.gc.ca/travel-voyage/cta-cap-SE.json", network.requests.single().url.toString())
        assertTrue(network.requests.single().cacheControl.noCache)
    }
}
