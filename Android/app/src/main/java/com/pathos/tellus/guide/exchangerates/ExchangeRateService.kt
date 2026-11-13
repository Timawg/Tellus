package com.pathos.tellus.guide.exchangerates

import com.pathos.tellus.core.network.NetworkService
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonObject
import okhttp3.CacheControl
import okhttp3.Request
import java.math.BigDecimal
import java.math.MathContext
import java.text.NumberFormat
import java.time.Clock
import java.time.Duration
import java.time.Instant
import java.util.Locale
import javax.inject.Inject
import javax.inject.Singleton

/** Daily rates from one currency to every other, from currency-api. */
data class ExchangeRates(
    val base: String,
    val date: String,
    /** Units of each currency per one unit of [base], keyed by uppercase code. */
    val rates: Map<String, Double>,
) {
    companion object {
        /**
         * The response is `{"date": "2026-11-04", "sek": {"eur": 0.091, …}}`,
         * keyed by the lowercase base code, so it's decoded by hand.
         */
        fun parse(json: Json, text: String): ExchangeRates {
            val root = json.parseToJsonElement(text).jsonObject
            val date = (root["date"] as? JsonPrimitive)?.contentOrNull
                ?: throw SerializationException("No date in response")
            val (baseKey, raw) = root.entries.firstOrNull { it.key != "date" && it.value is JsonObject }
                ?: throw SerializationException("No rates in response")
            val rates = raw.jsonObject.mapNotNull { (code, value) ->
                (value as? JsonPrimitive)?.doubleOrNull?.let { code.uppercase() to it }
            }.toMap()
            return ExchangeRates(baseKey.uppercase(), date, rates)
        }
    }
}

/** How much of a destination's currency one unit of the home currency buys. */
data class ExchangeRate(val home: String, val destination: String, val rate: Double, val date: String) {
    /** One unit of the destination currency in the home currency. */
    val inverse: Double get() = 1 / rate

    companion object {
        /** "16.63", "0.06011", "1,534": four significant digits reads well for both tiny and large rates. */
        fun format(value: Double, locale: Locale): String {
            val rounded = BigDecimal(value).round(MathContext(4)).stripTrailingZeros()
            return NumberFormat.getNumberInstance(locale).apply {
                maximumFractionDigits = maxOf(rounded.scale(), 0)
                minimumFractionDigits = 0
            }.format(rounded)
        }
    }
}

interface ExchangeRateService {
    /** Today's rates from [base] (an ISO 4217 code) to every other currency. */
    suspend fun getRates(base: String): ExchangeRates
}

/**
 * Daily exchange rates from fawazahmed0/currency-api, which needs no API key.
 * The Cloudflare mirror revalidates on every request; jsDelivr is the
 * fallback, but it marks files cacheable for a week, so its copy is never
 * read from the local cache. Rates are kept for an hour per base currency.
 */
@Singleton
class CurrencyApiExchangeRateService @Inject constructor(
    private val networkService: NetworkService,
    private val json: Json,
    private val clock: Clock,
) : ExchangeRateService {

    private val mutex = Mutex()
    private val cache = mutableMapOf<String, Pair<Instant, ExchangeRates>>()

    override suspend fun getRates(base: String): ExchangeRates {
        val key = base.uppercase()
        require(key.isNotEmpty() && key.all { it in 'A'..'Z' }) { "Invalid currency code: $base" }
        mutex.withLock { cache[key] }?.let { (fetched, rates) ->
            if (Duration.between(fetched, clock.instant()) < LIFETIME) return rates
        }
        val rates = try {
            fetch(key, fallback = false)
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            fetch(key, fallback = true)
        }
        mutex.withLock { cache[key] = clock.instant() to rates }
        return rates
    }

    private suspend fun fetch(base: String, fallback: Boolean): ExchangeRates {
        val root = if (fallback) FALLBACK_ROOT_URL else ROOT_URL
        val request = Request.Builder()
            .url("$root/currencies/${base.lowercase()}.json")
            .apply { if (fallback) cacheControl(CacheControl.FORCE_NETWORK) }
            .build()
        return ExchangeRates.parse(json, networkService.send(request).decodeToString())
    }

    private companion object {
        const val ROOT_URL = "https://latest.currency-api.pages.dev/v1"
        const val FALLBACK_ROOT_URL = "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1"
        val LIFETIME: Duration = Duration.ofHours(1)
    }
}
