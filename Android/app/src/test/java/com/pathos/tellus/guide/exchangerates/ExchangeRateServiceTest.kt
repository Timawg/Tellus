package com.pathos.tellus.guide.exchangerates

import com.pathos.tellus.core.network.HttpError
import com.pathos.tellus.testing.FakeNetworkService
import com.pathos.tellus.testing.MutableClock
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import okhttp3.CacheControl
import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.Duration
import java.util.Locale

class ExchangeRateServiceTest {

    private val json = Json { ignoreUnknownKeys = true }
    private val clock = MutableClock()
    private val body = """{"date":"2026-11-13","sek":{"eur":0.0868,"usd":0.1003,"btc":"n/a"}}"""

    @Test
    fun parsesRatesKeyedByLowercaseBase() {
        val rates = ExchangeRates.parse(json, body)
        assertEquals("SEK", rates.base)
        assertEquals("2026-11-13", rates.date)
        assertEquals(mapOf("EUR" to 0.0868, "USD" to 0.1003), rates.rates)
    }

    @Test
    fun fallsBackToJsDelivrWithoutLocalCache() = runTest {
        val network = FakeNetworkService(
            mapOf(
                "pages.dev" to { throw HttpError.InvalidStatus(503, ByteArray(0)) },
                "jsdelivr" to { body },
            ),
        )
        val rates = CurrencyApiExchangeRateService(network, json, clock).getRates("sek")

        assertEquals(0.0868, rates.rates.getValue("EUR"), 0.0)
        val fallback = network.requests.last()
        assertEquals("https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/sek.json", fallback.url.toString())
        assertEquals(CacheControl.FORCE_NETWORK.toString(), fallback.cacheControl.toString())
    }

    @Test
    fun keepsRatesForAnHour() = runTest {
        val network = FakeNetworkService(mapOf("pages.dev" to { body }))
        val service = CurrencyApiExchangeRateService(network, json, clock)
        service.getRates("SEK")
        clock.now = clock.now.plus(Duration.ofMinutes(59))
        service.getRates("sek")
        assertEquals(1, network.requests.size)

        clock.now = clock.now.plus(Duration.ofMinutes(2))
        service.getRates("SEK")
        assertEquals(2, network.requests.size)
    }

    @Test(expected = IllegalArgumentException::class)
    fun rejectsInvalidCode() = runTest {
        CurrencyApiExchangeRateService(FakeNetworkService(emptyMap()), json, clock).getRates("../x")
    }

    @Test
    fun formatsFourSignificantDigits() {
        assertEquals("16.63", ExchangeRate.format(16.6312, Locale.US))
        assertEquals("0.06011", ExchangeRate.format(0.060114, Locale.US))
        assertEquals("1,534", ExchangeRate.format(1534.2, Locale.US))
        assertEquals("11,52", ExchangeRate.format(11.523, Locale.GERMANY))
        assertEquals("12,350", ExchangeRate.format(12345.0, Locale.US))
    }
}
