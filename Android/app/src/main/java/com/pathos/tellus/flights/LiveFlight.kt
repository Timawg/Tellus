package com.pathos.tellus.flights

import com.pathos.tellus.map.Coordinate
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.longOrNull
import java.time.Instant

/**
 * An aircraft's latest position and live values, whichever feed it came
 * from. OpenSky covers civil and military traffic in the visible area;
 * adsb.lol's military list replaces OpenSky's data for the aircraft it knows
 * to be military, which are then drawn in a different colour. Ported from iOS
 * `LiveFlight`.
 */
data class LiveFlight(
    /** ICAO 24-bit address in lowercase hex, e.g. "ae1ffc". */
    val id: String,
    val callsign: String?,
    val coordinate: Coordinate,
    /** Degrees clockwise from north. */
    val track: Double?,
    val altitudeMeters: Double?,
    val isOnGround: Boolean,
    val speedMetersPerSecond: Double?,
    val verticalRateMetersPerSecond: Double?,
    val squawk: String?,
    /** OpenSky: country of registration, from the address block. */
    val originCountry: String?,
    /** adsb.lol: ICAO type designator, e.g. "C17". */
    val typeCode: String?,
    val registration: String?,
    /** adsb.lol: "general", "nordo", "unlawful"…; null when there is none. */
    val emergency: String?,
    val lastContact: Instant,
    val source: Source,
) {
    enum class Source {
        OPEN_SKY,

        /** adsb.lol's list of aircraft flagged as military. */
        ADSB_LOL_MILITARY,
    }

    val isMilitary: Boolean get() = source == Source.ADSB_LOL_MILITARY
}

/**
 * OpenSky's flights with adsb.lol's military aircraft merged in by ICAO
 * address. A military entry replaces the OpenSky one for the same aircraft;
 * military aircraft OpenSky didn't list are added, so they still show while
 * OpenSky is rate limiting us.
 */
fun List<LiveFlight>.merging(military: List<LiveFlight>): List<LiveFlight> {
    if (military.isEmpty()) return this
    // The first entry wins for a repeated address, as on iOS.
    val militaryById = military.reversed().associateBy { it.id }
    val listed = map { it.id }.toSet()
    return map { militaryById[it.id] ?: it } + military.filter { it.id !in listed }
}

/** OpenSky's `/states/all` response: `{"time": …, "states": [[icao24, callsign, …], …]}`. */
object OpenSkyStates {

    fun parse(json: Json, text: String): List<LiveFlight> {
        val states = json.parseToJsonElement(text).jsonObject["states"]
        if (states == null || states is JsonNull) return emptyList()
        return states.jsonArray.mapNotNull { state -> flight(state.jsonArray) }
    }

    /**
     * One state vector, read by position like iOS `StateVector`. Vectors
     * without a position are skipped; a malformed vector fails the whole
     * response, as decoding does on iOS.
     */
    private fun flight(state: JsonArray): LiveFlight? {
        fun string(index: Int) = (state.getOrNull(index) as? JsonPrimitive)?.takeIf { it.isString }?.contentOrNull
        fun number(index: Int) = (state.getOrNull(index) as? JsonPrimitive)?.doubleOrNull
        val icao24 = string(0) ?: throw SerializationException("No icao24")
        val lastContact = (state.getOrNull(4) as? JsonPrimitive)?.longOrNull ?: throw SerializationException("No last contact")
        val onGround = (state.getOrNull(8) as? JsonPrimitive)?.booleanOrNull ?: throw SerializationException("No on_ground")
        val latitude = number(6) ?: return null
        val longitude = number(5) ?: return null
        val callsign = string(1)?.trim()?.takeIf { it.isNotEmpty() }
        return LiveFlight(
            id = icao24.lowercase(),
            callsign = callsign,
            coordinate = Coordinate(latitude, longitude),
            track = number(10),
            altitudeMeters = number(13) ?: number(7),
            isOnGround = onGround,
            speedMetersPerSecond = number(9),
            verticalRateMetersPerSecond = number(11),
            squawk = string(14),
            originCountry = string(2),
            typeCode = null,
            registration = null,
            emergency = null,
            lastContact = Instant.ofEpochSecond(lastContact),
            source = LiveFlight.Source.OPEN_SKY,
        )
    }
}

/** adsb.lol's readsb-style aircraft list, ported from iOS `ADSBLolAircraftList`. */
object AdsbLolAircraftList {

    /** Type designators for ground vehicles and fixed transmitters, which some military sites broadcast. */
    private val nonAircraftTypes = setOf("TWR", "GND", "SERV", "EMER")
    private const val METERS_PER_FOOT = 0.3048
    private const val METERS_PER_SECOND_PER_KNOT = 0.514444

    /**
     * Aircraft with a position from the last minute. Surface vehicles
     * (category C*) and transmitters are left out.
     */
    fun parse(json: Json, text: String, receivedAt: Instant): List<LiveFlight> {
        val root = json.parseToJsonElement(text).jsonObject
        val listTime = (root["now"] as? JsonPrimitive)?.doubleOrNull?.let { Instant.ofEpochMilli(it.toLong()) } ?: receivedAt
        val aircraft = root["ac"]?.jsonArray ?: throw SerializationException("No aircraft list")
        return aircraft.mapNotNull { element ->
            val a = element as? JsonObject ?: return@mapNotNull null
            fun string(key: String) = (a[key] as? JsonPrimitive)?.takeIf { it.isString }?.contentOrNull
            fun number(key: String) = (a[key] as? JsonPrimitive)?.takeIf { !it.isString }?.doubleOrNull
            val hex = string("hex") ?: return@mapNotNull null
            val lat = number("lat") ?: return@mapNotNull null
            val lon = number("lon") ?: return@mapNotNull null
            val seenPos = number("seen_pos") ?: 0.0
            val type = string("t")
            if (lat !in -90.0..90.0 || lon !in -180.0..180.0 || seenPos > 60 ||
                string("category")?.startsWith("C") == true || type.orEmpty() in nonAircraftTypes
            ) {
                return@mapNotNull null
            }
            // alt_baro is a number of feet, or "ground".
            val altBaro = a["alt_baro"] as? JsonPrimitive
            val onGround = altBaro?.isString == true
            val altitudeFeet = if (onGround) null else number("alt_geom") ?: altBaro?.doubleOrNull
            val callsign = string("flight")?.trim()?.takeIf { it.isNotEmpty() }
            LiveFlight(
                id = hex.lowercase(),
                callsign = callsign,
                coordinate = Coordinate(lat, lon),
                track = number("track") ?: number("true_heading"),
                altitudeMeters = altitudeFeet?.let { it * METERS_PER_FOOT },
                isOnGround = onGround,
                speedMetersPerSecond = number("gs")?.let { it * METERS_PER_SECOND_PER_KNOT },
                verticalRateMetersPerSecond = (number("baro_rate") ?: number("geom_rate"))?.let { it * METERS_PER_FOOT / 60 },
                squawk = string("squawk"),
                originCountry = null,
                typeCode = type?.takeIf { it.isNotEmpty() },
                registration = string("r")?.takeIf { it.isNotEmpty() },
                emergency = string("emergency")?.takeIf { it != "none" },
                lastContact = listTime.minusMillis((seenPos * 1000).toLong()),
                source = LiveFlight.Source.ADSB_LOL_MILITARY,
            )
        }
    }
}
