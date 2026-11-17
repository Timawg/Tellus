package com.pathos.tellus.hazards

import com.pathos.tellus.core.network.NetworkService
import com.pathos.tellus.map.Coordinate
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.CacheControl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.Request
import java.time.Clock
import java.time.Duration
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException
import javax.inject.Inject
import javax.inject.Singleton

/** An orange or red alert from GDACS, the UN and EU's Global Disaster Alert and Coordination System. */
data class DisasterAlert(
    val id: String,
    val kind: Kind,
    val level: Level,
    val name: String,
    val severity: String?,
    val start: Instant?,
    val end: Instant?,
    /** ISO 3166-1 alpha-2 codes of the countries affected. */
    val countryCodes: Set<String>,
    val reportUrl: String?,
) {
    enum class Kind(val code: String?, val title: String, val symbol: String) {
        CYCLONE("TC", "Tropical cyclone", "🌀"),
        // Drawn as a seismograph trace where it matters; see HazardSymbol.
        EARTHQUAKE("EQ", "Earthquake", "〰️"),
        FLOOD("FL", "Flood", "🌊"),
        VOLCANO("VO", "Volcano", "🌋"),
        DROUGHT("DR", "Drought", "☀️"),
        WILDFIRE("WF", "Wildfire", "🔥"),
        TSUNAMI("TS", "Tsunami", "🌊"),
        OTHER(null, "Disaster", "⚠️");

        companion object {
            fun of(code: String) = entries.firstOrNull { it.code == code }
        }
    }

    enum class Level(val title: String) { ORANGE("Orange"), RED("Red") }

    /**
     * Droughts last months and cover whole regions, so they're listed in the
     * guide but don't get a banner on the map card.
     */
    val isUrgent: Boolean get() = kind != Kind.DROUGHT
}

/** GDACS event list: a GeoJSON feature collection. */
@Serializable
data class GdacsEventList(val features: List<Feature>) {

    @Serializable
    data class Feature(val properties: Properties, val geometry: Geometry? = null)

    /** Events in the list are points: their centre, as [longitude, latitude]. */
    @Serializable
    data class Geometry(val coordinates: JsonElement? = null) {
        val point: Coordinate?
            get() {
                val pair = (coordinates as? JsonArray)?.mapNotNull { (it as? JsonPrimitive)?.doubleOrNull } ?: return null
                if (pair.size < 2 || pair[1] !in -90.0..90.0 || pair[0] !in -180.0..180.0) return null
                return Coordinate(pair[1], pair[0])
            }
    }

    @Serializable
    data class Properties(
        val eventtype: String,
        val eventid: Long,
        val episodeid: Long? = null,
        val name: String? = null,
        val country: String? = null,
        val alertlevel: String,
        @Serializable(with = FlexibleBooleanSerializer::class) val iscurrent: Boolean? = null,
        val fromdate: String? = null,
        val todate: String? = null,
        val affectedcountries: List<Country>? = null,
        val severitydata: Severity? = null,
        val url: Links? = null,
    )

    @Serializable
    data class Country(val iso2: String? = null, val countryname: String? = null)

    @Serializable
    data class Severity(val severitytext: String? = null)

    @Serializable
    data class Links(val report: String? = null)

    /**
     * Current orange and red alerts, red first. An event can be listed once
     * per episode; the latest episode wins.
     */
    val currentAlerts: List<DisasterAlert>
        get() {
            val seen = mutableSetOf<String>()
            return features.asReversed().mapNotNull { feature ->
                val p = feature.properties
                if (p.iscurrent == false) return@mapNotNull null
                val level = DisasterAlert.Level.entries.firstOrNull { it.title == p.alertlevel } ?: return@mapNotNull null
                val id = "${p.eventtype}-${p.eventid}"
                if (!seen.add(id)) return@mapNotNull null
                val kind = DisasterAlert.Kind.of(p.eventtype)
                DisasterAlert(
                    id = id,
                    kind = kind ?: DisasterAlert.Kind.OTHER,
                    level = level,
                    name = p.name ?: kind?.title ?: "Disaster",
                    severity = p.severitydata?.severitytext,
                    start = p.fromdate?.let(::parseDate),
                    end = p.todate?.let(::parseDate),
                    countryCodes = p.affectedcountries.orEmpty().mapNotNull { it.iso2?.uppercase() }.toSet(),
                    reportUrl = p.url?.report,
                )
            }.sortedWith(compareBy<DisasterAlert> { if (it.level == DisasterAlert.Level.RED) 0 else 1 }.thenBy { it.start ?: Instant.MIN })
        }

    // Not private: the serialization plugin adds serializer() to this companion.
    companion object {
        /** GDACS dates are UTC without a zone, e.g. "2026-05-21T00:00:00". */
        internal fun parseDate(text: String): Instant? = try {
            LocalDateTime.parse(text, DateTimeFormatter.ISO_LOCAL_DATE_TIME).toInstant(ZoneOffset.UTC)
        } catch (_: DateTimeParseException) {
            null
        }
    }
}

/** GDACS sends `"true"` as a string, but may send a real boolean. */
object FlexibleBooleanSerializer : KSerializer<Boolean?> {
    override val descriptor = PrimitiveSerialDescriptor("FlexibleBoolean", PrimitiveKind.BOOLEAN)

    override fun deserialize(decoder: Decoder): Boolean? {
        val primitive = (decoder as JsonDecoder).decodeJsonElement().jsonPrimitive
        return primitive.booleanOrNull ?: primitive.content.equals("true", ignoreCase = true)
    }

    override fun serialize(encoder: Encoder, value: Boolean?) {
        encoder.encodeBoolean(value == true)
    }
}

interface DisasterAlertService {
    /** Current orange and red alerts affecting the country (ISO alpha-2 code). */
    suspend fun getAlerts(countryCode: String): List<DisasterAlert>
}

/** Disaster alerts from GDACS, which needs no key. One list covers every country, kept for 30 minutes. */
@Singleton
class GdacsDisasterAlertService @Inject constructor(
    private val networkService: NetworkService,
    private val json: Json,
    private val clock: Clock,
) : DisasterAlertService {

    private val mutex = Mutex()
    private var cache: Pair<Instant, List<DisasterAlert>>? = null

    override suspend fun getAlerts(countryCode: String): List<DisasterAlert> {
        val code = countryCode.uppercase()
        return allAlerts().filter { code in it.countryCodes }
    }

    private suspend fun allAlerts(): List<DisasterAlert> {
        val now = clock.instant()
        mutex.withLock { cache }?.let { (fetched, alerts) ->
            if (Duration.between(fetched, now) < LIFETIME) return alerts
        }
        val day = DateTimeFormatter.ISO_LOCAL_DATE.withZone(ZoneOffset.UTC)
        val url = "$ROOT_URL/events/geteventlist/SEARCH".toHttpUrl().newBuilder()
            .addQueryParameter("alertlevel", "Orange;Red")
            .addQueryParameter("fromdate", day.format(now.minus(Duration.ofDays(30))))
            .addQueryParameter("todate", day.format(now))
            .build()
        val request = Request.Builder().url(url).cacheControl(CacheControl.FORCE_NETWORK).build()
        val alerts = json.decodeFromString<GdacsEventList>(networkService.send(request).decodeToString()).currentAlerts
        mutex.withLock { cache = now to alerts }
        return alerts
    }

    private companion object {
        const val ROOT_URL = "https://www.gdacs.org/gdacsapi/api"
        val LIFETIME: Duration = Duration.ofMinutes(30)
    }
}
