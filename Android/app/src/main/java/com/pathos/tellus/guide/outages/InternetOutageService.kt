package com.pathos.tellus.guide.outages

import com.pathos.tellus.core.network.NetworkService
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.CacheControl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.Request
import java.time.Clock
import java.time.Duration
import java.time.Instant
import javax.inject.Inject
import javax.inject.Singleton

/**
 * A period when a country's internet connectivity dropped, seen by at least
 * two of IODA's independent signals at the same time.
 */
data class InternetOutage(
    val start: Instant,
    val end: Instant,
    /** Still under way when the data was fetched. */
    val isOngoing: Boolean,
    /** Signals that saw it, e.g. "Routing (BGP)" and "Active probing". */
    val signals: List<String>,
)

/** IODA (Internet Outage Detection and Analysis, Georgia Tech) outage events. */
@Serializable
data class IodaEventList(val data: List<Event>) {

    @Serializable
    data class Event(val start: Double, val duration: Double, val datasource: String)

    /**
     * IODA flags many short blips from a single signal, which are usually
     * measurement noise. Only periods where two or more independent signals
     * overlap are kept, newest first.
     */
    fun corroboratedOutages(until: Instant): List<InternetOutage> {
        data class Cluster(val start: Double, var end: Double, val sources: MutableSet<String>)

        val clusters = mutableListOf<Cluster>()
        for (event in data.sortedBy { it.start }) {
            val end = event.start + event.duration
            val last = clusters.lastOrNull()
            if (last != null && event.start < last.end) {
                last.end = maxOf(last.end, end)
                last.sources += event.datasource
            } else {
                clusters += Cluster(event.start, end, mutableSetOf(event.datasource))
            }
        }
        val ongoingCutoff = until.epochSecond - 30 * 60.0
        return clusters
            .filter { it.sources.size >= 2 }
            .map { cluster ->
                InternetOutage(
                    start = Instant.ofEpochMilli((cluster.start * 1000).toLong()),
                    end = Instant.ofEpochMilli((cluster.end * 1000).toLong()),
                    isOngoing = cluster.end >= ongoingCutoff,
                    signals = cluster.sources.map { SIGNAL_NAMES[it] ?: it }.sorted(),
                )
            }
            .sortedByDescending { it.start }
    }

    // Not private: the serialization plugin adds serializer() to this companion.
    companion object {
        private val SIGNAL_NAMES = mapOf(
            "bgp" to "Routing (BGP)",
            "ping-slash24" to "Active probing",
            "merit-nt" to "Network telescope",
            "gtr" to "Google traffic",
        )
    }
}

interface InternetOutageService {
    /** Corroborated outages in the country (ISO alpha-2) over the last week. */
    suspend fun getOutages(countryCode: String): List<InternetOutage>
}

/** Internet outages from IODA, which needs no key. Kept for 15 minutes per country, as on iOS. */
@Singleton
class IodaInternetOutageService @Inject constructor(
    private val networkService: NetworkService,
    private val json: Json,
    private val clock: Clock,
) : InternetOutageService {

    private val mutex = Mutex()
    private val cache = mutableMapOf<String, Pair<Instant, List<InternetOutage>>>()

    override suspend fun getOutages(countryCode: String): List<InternetOutage> {
        val code = countryCode.uppercase()
        if (code.length != 2 || !code.all { it in 'A'..'Z' }) return emptyList()
        val now = clock.instant()
        mutex.withLock { cache[code] }?.let { (fetched, outages) ->
            if (Duration.between(fetched, now) < LIFETIME) return outages
        }
        val url = "$ROOT_URL/outages/events".toHttpUrl().newBuilder()
            .addQueryParameter("entityType", "country")
            .addQueryParameter("entityCode", code)
            .addQueryParameter("from", now.minus(Duration.ofDays(7)).epochSecond.toString())
            .addQueryParameter("until", now.epochSecond.toString())
            .addQueryParameter("limit", "200")
            .build()
        val request = Request.Builder().url(url).cacheControl(CacheControl.FORCE_NETWORK).build()
        val list = json.decodeFromString<IodaEventList>(networkService.send(request).decodeToString())
        val outages = list.corroboratedOutages(until = now)
        mutex.withLock { cache[code] = now to outages }
        return outages
    }

    private companion object {
        const val ROOT_URL = "https://api.ioda.inetintel.cc.gatech.edu/v2"
        val LIFETIME: Duration = Duration.ofMinutes(15)
    }
}
