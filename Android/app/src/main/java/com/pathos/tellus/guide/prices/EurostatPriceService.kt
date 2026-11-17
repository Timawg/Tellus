package com.pathos.tellus.guide.prices

import com.pathos.tellus.core.network.NetworkService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.Request
import java.text.Collator
import java.time.Clock
import java.time.Duration
import java.time.Instant
import javax.inject.Inject
import javax.inject.Singleton

/** Eurostat price level indices (EU27 = 100) by country, year and category. */
data class EurostatPriceLevels(
    private val areas: Map<String, Area>,
    val accessedAt: Instant,
    /** A refresh failed and these are the last good data. */
    val isStale: Boolean,
) {
    enum class Category(val code: String, val title: String) {
        OVERALL("E011", "Overall household prices"),
        GROCERIES("A0101", "Food and non-alcoholic drinks"),
        HOUSING("A0104", "Housing and utilities"),
        TRANSPORT("A0107", "Transport"),
        RESTAURANTS("A0111", "Restaurants and accommodation"),
    }

    data class Area(val id: String, val name: String, val prices: Map<Int, Map<Category, Double>>)

    data class Comparison(val year: Int, val changes: Map<Category, Double>)

    /** Areas the country can be compared with: the EU average first, then by name. */
    fun referenceAreas(countryCode: String, collator: Collator = Collator.getInstance()): List<Area> {
        val code = eurostatCode(countryCode)
        val country = areas[code] ?: return emptyList()
        return areas.values
            .filter { area -> area.id != code && area.prices.keys.any { it in country.prices } }
            .sortedWith(compareBy<Area> { it.id != EU_AVERAGE_CODE }.thenBy(collator) { it.name })
    }

    /** Price differences in the latest year both areas report, as fractions (0.12 = 12% higher). */
    fun comparison(countryCode: String, referenceCode: String): Comparison? {
        val country = areas[eurostatCode(countryCode)] ?: return null
        val reference = areas[referenceCode] ?: return null
        val year = country.prices.keys.filter { it in reference.prices }.maxOrNull() ?: return null
        val prices = country.prices.getValue(year)
        val referencePrices = reference.prices.getValue(year)
        val changes = prices.mapNotNull { (category, price) ->
            referencePrices[category]?.let { category to price / it - 1 }
        }.toMap()
        return Comparison(year, changes)
    }

    companion object {
        const val EU_AVERAGE_CODE = "EU27_2020"
        const val SOURCE_URL = "https://ec.europa.eu/eurostat/databrowser/view/prc_ppp_ind_1/default/table?lang=en"

        private fun eurostatCode(countryCode: String) = when (val code = countryCode.uppercase()) {
            "GR" -> "EL"
            "GB" -> "UK"
            else -> code
        }

        /** Reads Eurostat's JSON-stat cube for the price level indicator. */
        fun parse(json: Json, text: String, accessedAt: Instant): EurostatPriceLevels {
            val response = json.decodeFromString<JsonStat>(text)
            val id = response.id
            val size = response.size
            fun index(axis: String) = response.dimension[axis]?.category?.index
            val geography = response.dimension["geo"]?.category
            val timeIndex = index("time")
            val categoryIndex = index("ppp_cat18")
            val annual = index("freq")?.get("A")
            val priceIndex = index("indic_ppp")?.get("PLI_EU27_2020")
            if (id.size != size.size || id.toSet() != setOf("freq", "indic_ppp", "ppp_cat18", "geo", "time") ||
                geography == null || timeIndex == null || categoryIndex == null || annual == null || priceIndex == null
            ) {
                throw SerializationException("Unexpected Eurostat dimensions")
            }

            // JSON-stat flattens the cube with the last dimension varying fastest.
            val strides = mutableMapOf<String, Long>()
            var stride = 1L
            for ((axis, count) in id.zip(size).reversed()) {
                if (count <= 0 || axis in strides) throw SerializationException("Bad Eurostat size")
                strides[axis] = stride
                stride = Math.multiplyExact(stride, count.toLong())
            }

            fun offset(axis: String, index: Int?): Long? {
                val dimension = id.indexOf(axis)
                if (index == null || dimension < 0 || index !in 0 until size[dimension]) return null
                return index * strides.getValue(axis)
            }

            val frequency = offset("freq", annual) ?: throw SerializationException("No annual data")
            val indicator = offset("indic_ppp", priceIndex) ?: throw SerializationException("No price index")
            val areas = mutableMapOf<String, Area>()
            for ((code, geoIndex) in geography.index) {
                if (code.length != 2 && code != EU_AVERAGE_CODE) continue
                val place = offset("geo", geoIndex) ?: continue
                val observations = mutableMapOf<Int, Map<Category, Double>>()
                for ((year, yearIndex) in timeIndex) {
                    val number = year.toIntOrNull() ?: continue
                    val time = offset("time", yearIndex) ?: continue
                    val prices = Category.entries.mapNotNull { category ->
                        val group = offset("ppp_cat18", categoryIndex[category.code]) ?: return@mapNotNull null
                        val price = response.value[(frequency + indicator + place + time + group).toString()]
                        price?.takeIf { it > 0 && it.isFinite() }?.let { category to it }
                    }.toMap()
                    if (Category.OVERALL in prices) observations[number] = prices
                }
                if (observations.isEmpty()) continue
                val name = if (code == EU_AVERAGE_CODE) "EU average" else geography.label?.get(code) ?: code
                areas[code] = Area(code, name, observations)
            }
            if (EU_AVERAGE_CODE !in areas) throw SerializationException("No EU average")
            return EurostatPriceLevels(areas, accessedAt, isStale = false)
        }
    }

    @Serializable
    private data class JsonStat(
        val id: List<String>,
        val size: List<Int>,
        val dimension: Map<String, Dimension>,
        val value: Map<String, Double>,
    ) {
        @Serializable
        data class Dimension(val category: Category)

        @Serializable
        data class Category(val index: Map<String, Int>, val label: Map<String, String>? = null)
    }
}

interface PriceLevelService {
    suspend fun getPriceLevels(): EurostatPriceLevels
}

/**
 * Eurostat price levels, kept for a day. One download serves every
 * comparison. When a refresh fails, the last good data is returned marked
 * stale, as on iOS.
 */
@Singleton
class EurostatPriceService @Inject constructor(
    private val networkService: NetworkService,
    private val json: Json,
    private val clock: Clock,
) : PriceLevelService {

    // Refreshes run here rather than in the caller, so closing one country's
    // guide doesn't cancel a download another is waiting for. It lives as
    // long as this singleton, which is the app process.
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val mutex = Mutex()
    private var cached: EurostatPriceLevels? = null
    private var refresh: Deferred<EurostatPriceLevels>? = null

    override suspend fun getPriceLevels(): EurostatPriceLevels {
        val task = mutex.withLock {
            cached?.let { if (Duration.between(it.accessedAt, clock.instant()) < LIFETIME) return it }
            refresh ?: scope.async { refreshNow() }.also { refresh = it }
        }
        return task.await()
    }

    private suspend fun refreshNow(): EurostatPriceLevels {
        val result = try {
            val url = "$ROOT_URL/data/prc_ppp_ind_1".toHttpUrl().newBuilder()
                .addQueryParameter("lang", "en")
                .addQueryParameter("freq", "A")
                .addQueryParameter("indic_ppp", "PLI_EU27_2020")
                .apply { EurostatPriceLevels.Category.entries.forEach { addQueryParameter("ppp_cat18", it.code) } }
                .build()
            val text = networkService.send(Request.Builder().url(url).build()).decodeToString()
            EurostatPriceLevels.parse(json, text, clock.instant()).also { fresh -> mutex.withLock { cached = fresh } }
        } catch (error: Exception) {
            mutex.withLock { cached }?.copy(isStale = true) ?: run {
                mutex.withLock { refresh = null }
                throw error
            }
        }
        mutex.withLock { refresh = null }
        return result
    }

    private companion object {
        const val ROOT_URL = "https://ec.europa.eu/eurostat/api/dissemination/statistics/1.0"
        val LIFETIME: Duration = Duration.ofDays(1)
    }
}
