package com.pathos.tellus.hazards

import com.pathos.tellus.map.Coordinate
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonArray
import java.text.NumberFormat
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException
import java.util.Locale
import kotlin.math.abs

/**
 * Something happening in nature right now, drawn on the map's hazards layer:
 * an earthquake from USGS, a cyclone, flood, drought or wildfire from GDACS,
 * or an ongoing volcanic eruption from the Smithsonian. Ported from iOS
 * `NaturalHazard`.
 */
data class NaturalHazard(
    val id: String,
    val kind: DisasterAlert.Kind,
    val name: String,
    val coordinate: Coordinate,
    val severity: Severity,
    /** When an earthquake struck, or when anything else began. */
    val date: Instant?,
    /** GDACS: the latest update in its report. */
    val updated: Instant?,
    /** Where, e.g. "12 km SSW of Hualien City, Taiwan" or "Brazil, Guyana". */
    val place: String?,
    /** e.g. "Up to 157 km/h" or "6,306 ha burned". */
    val summary: String?,
    /** Earthquakes: magnitude and depth in kilometres. */
    val magnitude: Double?,
    val depth: Double?,
    /** Earthquakes: USGS flagged it in an ocean region where a tsunami is possible. */
    val mayCauseTsunami: Boolean,
    /** GDACS alert level or USGS PAGER level, e.g. "Orange". */
    val alertLevel: String?,
    /** Volcanoes: largest Volcanic Explosivity Index (0–8) of the eruption. */
    val explosivity: Int?,
    val source: Source,
    val url: String?,
    /** GDACS event and episode, for looking up a cyclone's track. */
    val gdacsEpisode: Pair<Long, Long>?,
) {
    enum class Severity { MINOR, MODERATE, SEVERE }

    enum class Source(val title: String) {
        USGS("USGS"),
        GDACS("GDACS"),
        SMITHSONIAN("Smithsonian Global Volcanism Program"),
    }
}

/** A tropical cyclone's path so far and GDACS's forecast for where it goes next. */
data class CycloneTrack(
    val hazardId: String,
    val severity: NaturalHazard.Severity,
    /** Short segments; drawn solid. */
    val observed: List<List<Coordinate>>,
    /** Drawn dashed. */
    val forecast: List<List<Coordinate>>,
)

/** [longitude, latitude] as GeoJSON writes it, or null when out of range. */
private fun coordinate(pair: List<Double>): Coordinate? {
    if (pair.size < 2 || pair[1] !in -90.0..90.0 || pair[0] !in -180.0..180.0) return null
    return Coordinate(pair[1], pair[0])
}

private fun numbers(element: JsonElement?): List<Double>? =
    (element as? JsonArray)?.mapNotNull { (it as? JsonPrimitive)?.doubleOrNull }

/** USGS's GeoJSON summary feed of recent earthquakes. */
@Serializable
data class UsgsEarthquakeFeed(val features: List<Feature>) {

    @Serializable
    data class Feature(val id: String, val properties: Properties, val geometry: Geometry? = null)

    @Serializable
    data class Properties(
        val mag: Double? = null,
        val place: String? = null,
        /** Milliseconds since 1970. */
        val time: Double? = null,
        val updated: Double? = null,
        val url: String? = null,
        val tsunami: Int? = null,
        /** PAGER impact level: green, yellow, orange or red. */
        val alert: String? = null,
        val type: String? = null,
    )

    /** Longitude, latitude, depth in km. */
    @Serializable
    data class Geometry(val coordinates: JsonElement? = null)

    val hazards: List<NaturalHazard>
        get() = features.mapNotNull { feature ->
            val p = feature.properties
            if (p.type != null && p.type != "earthquake") return@mapNotNull null
            val magnitude = p.mag ?: return@mapNotNull null
            val coordinates = numbers(feature.geometry?.coordinates) ?: return@mapNotNull null
            val location = coordinate(coordinates) ?: return@mapNotNull null
            val pager = p.alert?.lowercase()
            val severity = when {
                magnitude >= 6.5 || pager == "orange" || pager == "red" -> NaturalHazard.Severity.SEVERE
                magnitude >= 5.5 || pager == "yellow" -> NaturalHazard.Severity.MODERATE
                else -> NaturalHazard.Severity.MINOR
            }
            NaturalHazard(
                id = "usgs-${feature.id}",
                kind = DisasterAlert.Kind.EARTHQUAKE,
                name = "M ${String.format(Locale.getDefault(), "%.1f", magnitude)} earthquake",
                coordinate = location,
                severity = severity,
                date = p.time?.let { Instant.ofEpochMilli(it.toLong()) },
                updated = p.updated?.let { Instant.ofEpochMilli(it.toLong()) },
                place = p.place,
                summary = null,
                magnitude = magnitude,
                depth = coordinates.getOrNull(2),
                mayCauseTsunami = p.tsunami == 1,
                alertLevel = pager?.replaceFirstChar { it.uppercase() },
                explosivity = null,
                source = NaturalHazard.Source.USGS,
                url = p.url,
                gdacsEpisode = null,
            )
        }
}

/**
 * Current GDACS events of every alert level, one per event (its latest
 * episode). Earthquakes come from USGS instead, which lists more of them.
 */
val GdacsEventList.hazards: List<NaturalHazard>
    get() {
        val latest = LinkedHashMap<String, GdacsEventList.Feature>()
        for (feature in features) {
            val p = feature.properties
            if (p.iscurrent == false || p.eventtype == "EQ") continue
            val id = "gdacs-${p.eventtype}-${p.eventid}"
            val existing = latest[id]
            if (existing != null && (existing.properties.episodeid ?: 0) > (p.episodeid ?: 0)) continue
            latest[id] = feature
        }
        return latest.mapNotNull { (id, feature) ->
            val p = feature.properties
            val location = feature.geometry?.point ?: return@mapNotNull null
            val kind = DisasterAlert.Kind.of(p.eventtype) ?: DisasterAlert.Kind.OTHER
            val severity = when (p.alertlevel) {
                "Red" -> NaturalHazard.Severity.SEVERE
                "Orange" -> NaturalHazard.Severity.MODERATE
                else -> NaturalHazard.Severity.MINOR
            }
            val countries = p.affectedcountries.orEmpty().mapNotNull { it.countryname }
            NaturalHazard(
                id = id,
                kind = kind,
                name = p.name ?: kind.title,
                coordinate = location,
                severity = severity,
                date = p.fromdate?.let(GdacsEventList::parseDate),
                updated = p.todate?.let(GdacsEventList::parseDate),
                place = if (countries.isEmpty()) p.country else countries.joinToString(", "),
                summary = gdacsSummary(p.severitydata?.severitytext, kind),
                magnitude = null,
                depth = null,
                mayCauseTsunami = false,
                alertLevel = p.alertlevel,
                explosivity = null,
                source = NaturalHazard.Source.GDACS,
                url = p.url?.report,
                gdacsEpisode = p.episodeid?.let { p.eventid to it },
            )
        }
    }

/**
 * GDACS's severity line, tidied: "Green impact for forestfire in 6306 ha"
 * becomes "6,306 ha burned", "Hurricane/Typhoon > 74 mph (maximum wind speed
 * of 157 km/h)" becomes "Up to 157 km/h"; floods only say "Magnitude 0", so
 * nothing.
 */
fun gdacsSummary(raw: String?, kind: DisasterAlert.Kind, locale: Locale = Locale.getDefault()): String? {
    val text = raw?.trim()?.takeIf { it.isNotEmpty() } ?: return null
    if (kind == DisasterAlert.Kind.FLOOD && text.startsWith("Magnitude")) return null
    if (kind == DisasterAlert.Kind.WILDFIRE) {
        Regex("in (\\d+) ha").find(text)?.groupValues?.get(1)?.toIntOrNull()?.let {
            return "${NumberFormat.getIntegerInstance(locale).format(it)} ha burned"
        }
    }
    Regex("maximum wind speed of ([^)]+)").find(text)?.let { return "Up to ${it.groupValues[1]}" }
    return text
}

/** The shapes GDACS draws for one event. For a cyclone these include its track as two-point line segments. */
@Serializable
data class GdacsEventGeometry(val features: List<Feature>) {

    @Serializable
    data class Feature(val geometry: Geometry? = null, val properties: Properties)

    @Serializable
    data class Geometry(val type: String, val coordinates: JsonElement? = null)

    @Serializable
    data class Properties(@SerialName("Class") val className: String? = null, val forecast: Boolean? = null)

    fun track(hazard: NaturalHazard): CycloneTrack? {
        val observed = mutableListOf<List<Coordinate>>()
        val forecast = mutableListOf<List<Coordinate>>()
        for (feature in features) {
            val geometry = feature.geometry ?: continue
            if (feature.properties.className?.startsWith("Line_") != true || geometry.type != "LineString") continue
            val line = (geometry.coordinates as? JsonArray)?.mapNotNull { point -> numbers(point.jsonArray)?.let(::coordinate) }
                ?: continue
            if (line.size < 2) continue
            if (feature.properties.forecast == true) forecast += line else observed += line
        }
        if (observed.isEmpty() && forecast.isEmpty()) return null
        return CycloneTrack(hazard.id, hazard.severity, observed, forecast)
    }
}

/** Eruptions the Smithsonian's Global Volcanism Program lists as continuing, from its GeoServer. */
@Serializable
data class GvpEruptionFeed(val features: List<Feature>) {

    @Serializable
    data class Feature(val properties: Properties)

    @Serializable
    data class Properties(
        @SerialName("VolcanoNumber") val volcanoNumber: Int,
        @SerialName("VolcanoName") val volcanoName: String,
        @SerialName("ExplosivityIndexMax") val explosivityIndexMax: Int? = null,
        /** "yyyyMMdd". */
        @SerialName("StartDate") val startDate: String? = null,
        @SerialName("LatitudeDecimal") val latitude: Double,
        @SerialName("LongitudeDecimal") val longitude: Double,
    )

    val hazards: List<NaturalHazard>
        get() {
            // One per volcano: the most recent eruption.
            val latest = LinkedHashMap<Int, Properties>()
            for (feature in features) {
                val p = feature.properties
                val existing = latest[p.volcanoNumber]
                if (existing != null && existing.startDate.orEmpty() > p.startDate.orEmpty()) continue
                latest[p.volcanoNumber] = p
            }
            return latest.values.mapNotNull { p ->
                val location = coordinate(listOf(p.longitude, p.latitude)) ?: return@mapNotNull null
                NaturalHazard(
                    id = "gvp-${p.volcanoNumber}",
                    kind = DisasterAlert.Kind.VOLCANO,
                    name = displayName(p.volcanoName),
                    coordinate = location,
                    severity = if ((p.explosivityIndexMax ?: 0) >= 4) NaturalHazard.Severity.SEVERE else NaturalHazard.Severity.MODERATE,
                    date = p.startDate?.let(::parseStartDate),
                    updated = null,
                    place = null,
                    summary = null,
                    magnitude = null,
                    depth = null,
                    mayCauseTsunami = false,
                    alertLevel = null,
                    explosivity = p.explosivityIndexMax,
                    source = NaturalHazard.Source.SMITHSONIAN,
                    url = "https://volcano.si.edu/volcano.cfm?vn=${p.volcanoNumber}",
                    gdacsEpisode = null,
                )
            }
        }

    // Not private: the serialization plugin adds serializer() to this companion.
    companion object {
        /** "Ruiz, Nevado del" reads as "Nevado del Ruiz". */
        fun displayName(name: String): String {
            val parts = name.split(", ")
            return if (parts.size == 2) "${parts[1]} ${parts[0]}" else name
        }

        private fun parseStartDate(text: String): Instant? = try {
            LocalDate.parse(text, DateTimeFormatter.BASIC_ISO_DATE).atStartOfDay().toInstant(ZoneOffset.UTC)
        } catch (_: DateTimeParseException) {
            null
        }
    }
}

/** Drops GDACS volcano events at a volcano the Smithsonian already lists, keeping the Smithsonian's entry. */
fun List<NaturalHazard>.withoutDuplicateVolcanoes(): List<NaturalHazard> {
    val listed = filter { it.source == NaturalHazard.Source.SMITHSONIAN }.map { it.coordinate }
    return filter { hazard ->
        if (hazard.kind != DisasterAlert.Kind.VOLCANO || hazard.source != NaturalHazard.Source.GDACS) return@filter true
        listed.none { abs(it.latitude - hazard.coordinate.latitude) < 0.5 && abs(it.longitude - hazard.coordinate.longitude) < 0.5 }
    }
}
