package com.pathos.tellus.hazards

import com.pathos.tellus.core.network.NetworkService
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.DeserializationStrategy
import kotlinx.serialization.json.Json
import okhttp3.CacheControl
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.Request
import java.io.IOException
import java.time.Clock
import java.time.Duration
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import javax.inject.Inject
import javax.inject.Singleton

interface HazardService {
    /** Recent earthquakes, current GDACS events and ongoing eruptions worldwide. */
    suspend fun getHazards(): List<NaturalHazard>

    /** Path and forecast for a GDACS tropical cyclone. */
    suspend fun getTrack(cyclone: NaturalHazard): CycloneTrack?
}

/**
 * Natural hazards from three free sources that need no key: USGS
 * earthquakes, GDACS cyclones, floods, droughts and wildfires, and the
 * Smithsonian's list of continuing eruptions. Each source that answers is
 * used, so one being down doesn't empty the layer. Kept for 15 minutes.
 * Ported from iOS `HazardService`.
 */
@Singleton
class LiveHazardService @Inject constructor(
    private val networkService: NetworkService,
    private val json: Json,
    private val clock: Clock,
) : HazardService {

    private val mutex = Mutex()
    private var cache: Pair<Instant, List<NaturalHazard>>? = null
    private val tracks = mutableMapOf<String, CycloneTrack?>()

    override suspend fun getHazards(): List<NaturalHazard> = coroutineScope {
        val now = clock.instant()
        mutex.withLock { cache }?.let { (fetched, hazards) ->
            if (Duration.between(fetched, now) < LIFETIME) return@coroutineScope hazards
        }
        val monthAgo = now.minus(Duration.ofDays(30))

        val quakes = async { fetch("$USGS_ROOT/summary/4.5_week.geojson".toHttpUrl(), fresh = true, UsgsEarthquakeFeed.serializer()) }
        // GDACS lists at most 100 events per request, and there are many
        // small (green) wildfires, so those are left out: fires only show at
        // orange or red. The same goes for droughts, which cover whole
        // regions for months.
        val events = async { fetch(gdacsEvents("TC;FL;VO", "Green;Orange;Red", monthAgo, now), fresh = true, GdacsEventList.serializer()) }
        val alerts = async { fetch(gdacsEvents("WF;DR", "Orange;Red", monthAgo, now), fresh = true, GdacsEventList.serializer()) }
        val eruptions = async { fetch(continuingEruptions(), fresh = false, GvpEruptionFeed.serializer()) }

        val quakeFeed = quakes.await()
        val eventList = events.await()
        val alertList = alerts.await()
        val eruptionFeed = eruptions.await()
        if (quakeFeed == null && eventList == null && eruptionFeed == null) throw IOException("No hazard source answered")
        val hazards = (
            quakeFeed?.hazards.orEmpty() + eruptionFeed?.hazards.orEmpty() +
                eventList?.hazards.orEmpty() + alertList?.hazards.orEmpty()
            ).withoutDuplicateVolcanoes()
        mutex.withLock { cache = now to hazards }
        hazards
    }

    override suspend fun getTrack(cyclone: NaturalHazard): CycloneTrack? {
        if (cyclone.kind != DisasterAlert.Kind.CYCLONE) return null
        val (eventId, episodeId) = cyclone.gdacsEpisode ?: return null
        val key = "${cyclone.id}-$episodeId"
        mutex.withLock { if (key in tracks) return tracks[key] }
        val url = "$GDACS_ROOT/polygons/getgeometry".toHttpUrl().newBuilder()
            .addQueryParameter("eventtype", "TC")
            .addQueryParameter("eventid", eventId.toString())
            .addQueryParameter("episodeid", episodeId.toString())
            .build()
        val track = fetch(url, fresh = false, GdacsEventGeometry.serializer())?.track(cyclone)
        // Remembered even when null, so a cyclone without a track isn't asked for again.
        mutex.withLock { tracks[key] = track }
        return track
    }

    private fun gdacsEvents(types: String, levels: String, from: Instant, to: Instant): HttpUrl {
        val day = DateTimeFormatter.ISO_LOCAL_DATE.withZone(ZoneOffset.UTC)
        return "$GDACS_ROOT/events/geteventlist/SEARCH".toHttpUrl().newBuilder()
            .addQueryParameter("eventlist", types)
            .addQueryParameter("alertlevel", levels)
            .addQueryParameter("fromdate", day.format(from))
            .addQueryParameter("todate", day.format(to))
            .build()
    }

    private fun continuingEruptions(): HttpUrl = "$SMITHSONIAN_ROOT/ows".toHttpUrl().newBuilder()
        .addQueryParameter("service", "WFS")
        .addQueryParameter("version", "2.0.0")
        .addQueryParameter("request", "GetFeature")
        .addQueryParameter("typeName", "GVP-VOTW:E3WebApp_Eruptions1960")
        .addQueryParameter("outputFormat", "application/json")
        .addQueryParameter("CQL_FILTER", "ContinuingEruption='True'")
        .build()

    /**
     * Null when the request or decoding fails. GDACS answers an empty search
     * with 204 No Content, which is an empty list rather than an error.
     */
    private suspend fun <T> fetch(url: HttpUrl, fresh: Boolean, deserializer: DeserializationStrategy<T>): T? = try {
        val request = Request.Builder().url(url).apply { if (fresh) cacheControl(CacheControl.FORCE_NETWORK) }.build()
        val text = networkService.send(request).decodeToString().ifBlank { """{"features":[]}""" }
        json.decodeFromString(deserializer, text)
    } catch (error: CancellationException) {
        throw error
    } catch (_: Exception) {
        null
    }

    private companion object {
        const val USGS_ROOT = "https://earthquake.usgs.gov/earthquakes/feed/v1.0"
        const val GDACS_ROOT = "https://www.gdacs.org/gdacsapi/api"
        const val SMITHSONIAN_ROOT = "https://webservices.volcano.si.edu/geoserver/GVP-VOTW"
        val LIFETIME: Duration = Duration.ofMinutes(15)
    }
}
