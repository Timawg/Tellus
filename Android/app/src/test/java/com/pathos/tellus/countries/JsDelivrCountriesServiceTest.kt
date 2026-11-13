package com.pathos.tellus.countries

import com.pathos.tellus.core.network.HttpError
import com.pathos.tellus.core.network.NetworkService
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import okhttp3.Request
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class JsDelivrCountriesServiceTest {

    private class FakeNetwork(private val response: () -> String) : NetworkService {
        var lastUrl: String? = null
        override suspend fun send(request: Request): ByteArray {
            lastUrl = request.url.toString()
            return response().toByteArray()
        }
    }

    private val json = Json { ignoreUnknownKeys = true }

    @Test
    fun decodesCountriesAndIgnoresUnknownFields() = runTest {
        val network = FakeNetwork {
            """[{"name":{"common":"Sweden","official":"Kingdom of Sweden","native":{}},"cca2":"SE","cca3":"SWE",
               "area":450295,"borders":["FIN","NOR"],"translations":{"fra":{"official":"Royaume de Suède","common":"Suède"}},
               "latlng":[62,15],"population":10353442,"unknownField":true},
              {"name":{"common":"Nowhere"},"translations":{},"latlng":[0,0],"flags":{"png":"https://example.test/flag.png"}}]"""
        }
        val countries = JsDelivrCountriesService(network, json).getAllCountries()

        assertEquals("https://cdn.jsdelivr.net/gh/mledoze/countries@master/countries.json", network.lastUrl)
        val sweden = countries[0]
        assertEquals("Sweden", sweden.name?.common)
        assertEquals(listOf("FIN", "NOR"), sweden.borders)
        assertEquals(450295.0, sweden.area!!, 0.0)
        assertEquals("https://flagcdn.com/w320/se.png", sweden.flagUrl)
        // Sparse entries still decode; flags.png wins over the derived URL.
        assertNull(countries[1].cca3)
        assertEquals("https://example.test/flag.png", countries[1].flagUrl)
    }

    @Test(expected = SerializationException::class)
    fun missingRequiredFieldFailsLikeIos() = runTest {
        JsDelivrCountriesService(FakeNetwork { """[{"name":{"common":"Sweden"},"translations":{}}]""" }, json)
            .getAllCountries()
    }

    @Test(expected = HttpError.InvalidStatus::class)
    fun networkErrorsPropagate() = runTest {
        JsDelivrCountriesService(FakeNetwork { throw HttpError.InvalidStatus(500, ByteArray(0)) }, json)
            .getAllCountries()
    }
}
