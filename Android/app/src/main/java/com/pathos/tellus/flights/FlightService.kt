package com.pathos.tellus.flights

import com.pathos.tellus.core.network.HttpError
import com.pathos.tellus.core.network.NetworkService
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.Json
import okhttp3.CacheControl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.Request
import java.time.Clock
import java.time.Duration
import java.time.Instant
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.math.min
import kotlin.math.pow

/** A closed range of degrees, as in iOS `CoordinateSpan`. */
data class CoordinateSpan(val minimum: Double, val maximum: Double) {
    operator fun contains(value: Double) = value in minimum..maximum
}

/** Tracks when a rate-limited API may be called again, ported from iOS `RateLimitBackoff`. */
class RateLimitBackoff {
    var resumeAt: Instant? = null
        private set
    private var consecutiveLimits = 0

    /** Seconds left before calls are allowed again, or null if they are allowed now. */
    fun remainingDelay(now: Instant): Double? {
        val resume = resumeAt ?: return null
        if (!resume.isAfter(now)) return null
        return Duration.between(now, resume).toMillis() / 1000.0
    }

    fun recordRateLimit(retryAfterSeconds: Double?, now: Instant) {
        consecutiveLimits++
        // Used when the server doesn't say how long to wait: 30 s, 60 s, 120 s … capped at 15 minutes.
        val fallback = min(BASE_DELAY_SECONDS * 2.0.pow(consecutiveLimits - 1), MAX_DELAY_SECONDS)
        resumeAt = now.plusMillis(((retryAfterSeconds ?: fallback) * 1000).toLong())
    }

    fun reset() {
        resumeAt = null
        consecutiveLimits = 0
    }

    private companion object {
        const val BASE_DELAY_SECONDS = 30.0
        const val MAX_DELAY_SECONDS = 15 * 60.0
    }
}

interface FlightService {
    /** Aircraft OpenSky sees in the area. */
    suspend fun getFlights(latitudeSpan: CoordinateSpan?, longitudeSpan: CoordinateSpan?): List<LiveFlight>

    /** Aircraft adsb.lol flags as military, worldwide. */
    suspend fun getMilitaryFlights(): List<LiveFlight>
}

/**
 * Live aircraft positions from two free feeds: OpenSky for everything in the
 * visible area, and adsb.lol for the aircraft its database flags as military
 * (a few hundred worldwide, about 170 KB, so it's asked at most every 30
 * seconds). Ported from iOS `FlightService`.
 *
 * OpenSky limits anonymous use with a daily quota and answers 429 with the
 * number of seconds until it resets. While that window is open OpenSky
 * requests throw [HttpError.RateLimited] without touching the network, so the
 * 15 second polling doesn't keep hitting the API; adsb.lol is unaffected.
 */
@Singleton
class OpenSkyFlightService @Inject constructor(
    private val networkService: NetworkService,
    private val json: Json,
    private val clock: Clock,
) : FlightService {

    private val mutex = Mutex()
    private val backoff = RateLimitBackoff()
    private var militaryCache: Pair<Instant, List<LiveFlight>>? = null

    override suspend fun getFlights(latitudeSpan: CoordinateSpan?, longitudeSpan: CoordinateSpan?): List<LiveFlight> {
        mutex.withLock { backoff.remainingDelay(clock.instant()) }?.let { throw HttpError.RateLimited(it) }
        val url = "$ROOT_URL/states/all".toHttpUrl().newBuilder().apply {
            latitudeSpan?.let {
                addQueryParameter("lamin", it.minimum.toString())
                addQueryParameter("lamax", it.maximum.toString())
            }
            longitudeSpan?.let {
                addQueryParameter("lomin", it.minimum.toString())
                addQueryParameter("lomax", it.maximum.toString())
            }
        }.build()
        val text = try {
            networkService.send(Request.Builder().url(url).build()).decodeToString()
        } catch (error: HttpError.RateLimited) {
            // Report the wait actually applied, which includes the fallback
            // delay when the server didn't give one.
            val limitedAt = clock.instant()
            val remaining = mutex.withLock {
                backoff.recordRateLimit(error.retryAfterSeconds, limitedAt)
                backoff.remainingDelay(limitedAt)
            }
            throw HttpError.RateLimited(remaining)
        }
        mutex.withLock { backoff.reset() }
        return OpenSkyStates.parse(json, text)
    }

    override suspend fun getMilitaryFlights(): List<LiveFlight> {
        mutex.withLock { militaryCache }?.let { (fetched, flights) ->
            if (Duration.between(fetched, clock.instant()) < MILITARY_INTERVAL) return flights
        }
        val request = Request.Builder().url("$MILITARY_ROOT_URL/v2/mil").cacheControl(CacheControl.FORCE_NETWORK).build()
        val flights = AdsbLolAircraftList.parse(json, networkService.send(request).decodeToString(), clock.instant())
        mutex.withLock { militaryCache = clock.instant() to flights }
        return flights
    }

    private companion object {
        const val ROOT_URL = "https://opensky-network.org/api"
        const val MILITARY_ROOT_URL = "https://api.adsb.lol"
        val MILITARY_INTERVAL: Duration = Duration.ofSeconds(30)
    }
}
