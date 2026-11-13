package com.pathos.tellus.guide.profile

import com.pathos.tellus.core.network.HttpError
import com.pathos.tellus.testing.FakeNetworkService
import com.pathos.tellus.testing.MutableClock
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.time.Duration

class WorldBankCountryProfileServiceTest {

    private val json = Json { ignoreUnknownKeys = true }
    private val clock = MutableClock()

    private fun row(indicator: String, date: String, value: String) =
        """{"indicator":{"id":"$indicator","value":"x"},"date":"$date","value":$value}"""

    @Test
    fun keepsLatestObservationPerIndicator() = runTest {
        val body = """[{"page":1,"total":4},[
            ${row("SP.POP.TOTL", "2024", "10551707")},
            ${row("SP.POP.TOTL", "2023", "10500000")},
            ${row("NY.GDP.MKTP.CD", "2024", "null")},
            ${row("IT.NET.USER.ZS", "2023", "95.7")}
        ]]"""
        val network = FakeNetworkService(mapOf("worldbank" to { body }))
        val profile = WorldBankCountryProfileService(network, json, clock).getProfile("se")

        assertEquals(
            listOf(
                CountryIndicatorObservation(CountryIndicator.POPULATION, 10551707.0, 2024),
                CountryIndicatorObservation(CountryIndicator.INTERNET_USE, 95.7, 2023),
            ),
            profile,
        )
        val url = network.requests.single().url
        assertTrue(url.encodedPath, url.encodedPath.startsWith("/v2/country/SE/indicator/SP.POP.TOTL;NY.GDP.MKTP.CD;"))
        assertEquals("1", url.queryParameter("mrnev"))
    }

    @Test
    fun unsupportedCountryMeansNoData() = runTest {
        val network = FakeNetworkService(mapOf("worldbank" to { """[{"message":[{"id":"120","key":"Invalid value"}]}]""" }))
        assertEquals(emptyList<CountryIndicatorObservation>(), WorldBankCountryProfileService(network, json, clock).getProfile("XK"))
    }

    @Test(expected = SerializationException::class)
    fun otherApiErrorsFail() = runTest {
        val network = FakeNetworkService(mapOf("worldbank" to { """[{"message":[{"id":"175"}]}]""" }))
        WorldBankCountryProfileService(network, json, clock).getProfile("SE")
    }

    @Test
    fun invalidCodeSkipsTheNetwork() = runTest {
        val network = FakeNetworkService(emptyMap())
        assertEquals(emptyList<AnnualObservation>(), WorldBankCountryProfileService(network, json, clock).getHomicideTrend("SWE"))
        assertTrue(network.requests.isEmpty())
    }

    @Test
    fun homicideTrendDropsNegativesAndRepeatsAndSortsByYear() = runTest {
        val body = """[{"total":4},[
            ${row(WorldBankCountryProfileService.HOMICIDE_INDICATOR, "2022", "1.1")},
            ${row(WorldBankCountryProfileService.HOMICIDE_INDICATOR, "2020", "1.3")},
            ${row(WorldBankCountryProfileService.HOMICIDE_INDICATOR, "2022", "9.9")},
            ${row(WorldBankCountryProfileService.HOMICIDE_INDICATOR, "2021", "-1")}
        ]]"""
        val network = FakeNetworkService(mapOf("worldbank" to { body }))
        val trend = WorldBankCountryProfileService(network, json, clock).getHomicideTrend("SE")
        assertEquals(listOf(AnnualObservation(2020, 1.3), AnnualObservation(2022, 1.1)), trend)
    }

    @Test
    fun rateLimitPausesHomicideRequestsUntilRetryAfter() = runTest {
        var limited = true
        val network = FakeNetworkService(
            mapOf("worldbank" to { if (limited) throw HttpError.RateLimited(60.0) else """[{"total":0}]""" }),
        )
        val service = WorldBankCountryProfileService(network, json, clock)
        repeat(2) {
            try {
                service.getHomicideTrend("SE")
                fail("Expected rate limit")
            } catch (_: HttpError.RateLimited) {
            }
        }
        assertEquals(1, network.requests.size)

        limited = false
        clock.now = clock.now.plus(Duration.ofSeconds(61))
        assertEquals(emptyList<AnnualObservation>(), service.getHomicideTrend("SE"))
        assertEquals(2, network.requests.size)
    }
}
