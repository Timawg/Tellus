package com.pathos.tellus.guide.profile

import com.pathos.tellus.core.network.HttpError
import com.pathos.tellus.core.network.NetworkService
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.Request
import java.time.Clock
import java.time.Instant
import javax.inject.Inject
import javax.inject.Singleton

data class AnnualObservation(val year: Int, val value: Double)

enum class CountryIndicator(val code: String, val title: String, val category: Category) {
    POPULATION("SP.POP.TOTL", "Total population", Category.POPULATION),
    GDP("NY.GDP.MKTP.CD", "GDP", Category.ECONOMY),
    GDP_PER_CAPITA("NY.GDP.PCAP.CD", "GDP per capita", Category.ECONOMY),
    SURFACE_AREA("AG.SRF.TOTL.K2", "Surface area", Category.GEOGRAPHY),
    INTERNET_USE("IT.NET.USER.ZS", "People using the internet", Category.INFRASTRUCTURE),
    ELECTRICITY_ACCESS("EG.ELC.ACCS.ZS", "People with electricity access", Category.INFRASTRUCTURE);

    enum class Category(val title: String) {
        POPULATION("Population"),
        ECONOMY("Economy"),
        GEOGRAPHY("Geography"),
        INFRASTRUCTURE("Infrastructure"),
    }
}

data class CountryIndicatorObservation(val indicator: CountryIndicator, val value: Double, val year: Int)

interface CountryProfileService {
    suspend fun getProfile(countryCode: String): List<CountryIndicatorObservation>
    suspend fun getHomicideTrend(countryCode: String): List<AnnualObservation>
}

/** World Bank World Development Indicators for a country, as in iOS `CountryProfileService`. */
@Singleton
class WorldBankCountryProfileService @Inject constructor(
    private val networkService: NetworkService,
    private val json: Json,
    private val clock: Clock,
) : CountryProfileService {

    private val mutex = Mutex()
    private val cache = mutableMapOf<String, List<CountryIndicatorObservation>>()
    private val homicideCache = mutableMapOf<String, List<AnnualObservation>>()
    private var homicideRetryAt: Instant? = null

    override suspend fun getProfile(countryCode: String): List<CountryIndicatorObservation> {
        val code = normalizedCode(countryCode) ?: return emptyList()
        mutex.withLock { cache[code] }?.let { return it }

        val indicators = CountryIndicator.entries
        val rows = fetch(code, indicators.map { it.code }, periods = 1)
        val observations = indicators.mapNotNull { indicator ->
            annualObservations(rows, indicator.code)
                .maxByOrNull { it.year }
                ?.let { CountryIndicatorObservation(indicator, it.value, it.year) }
        }
        mutex.withLock { cache[code] = observations }
        return observations
    }

    override suspend fun getHomicideTrend(countryCode: String): List<AnnualObservation> {
        val code = normalizedCode(countryCode) ?: return emptyList()
        mutex.withLock { homicideCache[code] }?.let { return it }
        mutex.withLock { homicideRetryAt }?.let { retryAt ->
            val now = clock.instant()
            if (retryAt.isAfter(now)) throw HttpError.RateLimited((retryAt.toEpochMilli() - now.toEpochMilli()) / 1000.0)
        }

        val rows = try {
            fetch(code, listOf(HOMICIDE_INDICATOR), periods = 10)
        } catch (error: HttpError.RateLimited) {
            error.retryAfterSeconds?.let { seconds ->
                mutex.withLock { homicideRetryAt = clock.instant().plusMillis((seconds * 1000).toLong()) }
            }
            throw error
        }
        val reportedYears = mutableSetOf<Int>()
        val trend = annualObservations(rows, HOMICIDE_INDICATOR)
            .filter { it.value >= 0 && reportedYears.add(it.year) }
            .sortedBy { it.year }
        mutex.withLock { homicideCache[code] = trend }
        return trend
    }

    private suspend fun fetch(code: String, indicators: List<String>, periods: Int): List<JsonObject> {
        val url = "$ROOT_URL/country/$code/indicator/${indicators.joinToString(";")}".toHttpUrl().newBuilder()
            .addQueryParameter("source", "2") // World Development Indicators
            .addQueryParameter("format", "json")
            .addQueryParameter("mrnev", periods.toString())
            .addQueryParameter("per_page", "50")
            .build()
        return parseRows(json, networkService.send(Request.Builder().url(url).build()).decodeToString())
    }

    companion object {
        private const val ROOT_URL = "https://api.worldbank.org/v2"
        const val HOMICIDE_INDICATOR = "VC.IHR.PSRC.P5"

        private fun normalizedCode(countryCode: String): String? {
            val code = countryCode.uppercase()
            return code.takeIf { it.length == 2 && it.all { char -> char in 'A'..'Z' } }
        }

        /**
         * The response is `[metadata, rows]`. The API answers HTTP 200 with
         * error 120 for unsupported country codes, which counts as no data;
         * any other error message is an invalid response.
         */
        fun parseRows(json: Json, text: String): List<JsonObject> {
            val array = json.parseToJsonElement(text).jsonArray
            val metadata = array.getOrNull(0) as? JsonObject ?: throw SerializationException("No metadata")
            val messages = metadata["message"] as? JsonArray
            if (messages != null) {
                val id = (messages.firstOrNull() as? JsonObject)?.get("id")?.let { (it as? JsonPrimitive)?.contentOrNull }
                if (id == "120") return emptyList()
                throw SerializationException("World Bank error $id")
            }
            val total = (metadata["total"] as? JsonPrimitive)?.intOrNull ?: throw SerializationException("No total")
            if (total == 0) return emptyList()
            return (array.getOrNull(1) as? JsonArray)?.mapNotNull { it as? JsonObject }
                ?: throw SerializationException("No rows")
        }

        private fun annualObservations(rows: List<JsonObject>, indicator: String): List<AnnualObservation> =
            rows.mapNotNull { row ->
                val id = (row["indicator"] as? JsonObject)?.get("id")?.let { (it as? JsonPrimitive)?.contentOrNull }
                val value = (row["value"] as? JsonPrimitive)?.doubleOrNull
                val year = (row["date"] as? JsonPrimitive)?.contentOrNull?.toIntOrNull()
                if (id != indicator || value == null || !value.isFinite() || year == null || year <= 0) return@mapNotNull null
                AnnualObservation(year, value)
            }
    }
}
