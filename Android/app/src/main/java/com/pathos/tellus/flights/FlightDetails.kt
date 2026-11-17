package com.pathos.tellus.flights

import com.pathos.tellus.core.network.HttpError
import com.pathos.tellus.core.network.NetworkService
import com.pathos.tellus.map.Coordinate
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.Request
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.math.asin
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

/** An aircraft's registration details from adsbdb.com, looked up by its ICAO 24-bit address. */
@Serializable
data class AircraftInfo(
    val type: String? = null,
    @SerialName("icao_type") val icaoType: String? = null,
    val manufacturer: String? = null,
    val registration: String? = null,
    @SerialName("registered_owner") val registeredOwner: String? = null,
    @SerialName("registered_owner_country_name") val registeredOwnerCountryName: String? = null,
    @SerialName("url_photo") val urlPhoto: String? = null,
) {
    /** "Boeing 737-8AS", or whichever part is known. */
    val displayType: String?
        get() = listOf(manufacturer, type).filter { !it.isNullOrEmpty() }.takeIf { it.isNotEmpty() }?.joinToString(" ")
}

/** A flight's scheduled route from adsbdb.com, looked up by callsign. */
@Serializable
data class FlightRoute(
    val callsign: String,
    /** The flight number passengers see, e.g. EN8HK for callsign DLA8HK. */
    @SerialName("callsign_iata") val callsignIata: String? = null,
    val airline: Airline? = null,
    val origin: Airport,
    val destination: Airport,
) {
    @Serializable
    data class Airline(val name: String? = null, val iata: String? = null, val icao: String? = null)

    @Serializable
    data class Airport(
        val name: String,
        val municipality: String? = null,
        @SerialName("country_name") val countryName: String? = null,
        @SerialName("iata_code") val iataCode: String? = null,
        @SerialName("icao_code") val icaoCode: String? = null,
        val latitude: Double,
        val longitude: Double,
    ) {
        /** IATA code (FRA) if it has one, otherwise ICAO (EDDF). */
        val code: String get() = iataCode ?: icaoCode ?: "—"
        val coordinate: Coordinate get() = Coordinate(latitude, longitude)
    }

    /** Origin, aircraft and destination for the map line, or null if the airports can't be drawn. */
    fun mapCoordinates(aircraft: Coordinate): List<Coordinate>? {
        if (!hasValidAirportCoordinates || !aircraft.isValid || Geo.distance(origin.coordinate, destination.coordinate) <= 0) return null
        return listOf(origin.coordinate, aircraft, destination.coordinate)
    }

    private val hasValidAirportCoordinates: Boolean
        get() = origin.coordinate.isValid && destination.coordinate.isValid

    /** How far along the route the aircraft is, measured via its position, in metres. */
    fun progress(aircraft: Coordinate): Triple<Double, Double, Double> {
        val flown = Geo.distance(origin.coordinate, aircraft)
        val remaining = Geo.distance(aircraft, destination.coordinate)
        val total = flown + remaining
        return Triple(flown, remaining, if (total > 0) flown / total else 0.0)
    }

    /**
     * Routes are crowd-sourced and keyed only by callsign, so they can be
     * stale or belong to another leg of a multi-stop flight. A route is only
     * believable if the aircraft is roughly between its two airports: the
     * detour via the aircraft's position may be at most 25% (plus 300 km for
     * departures, arrivals and holding patterns) longer than the direct route.
     */
    fun isPlausible(aircraft: Coordinate): Boolean {
        if (!hasValidAirportCoordinates || !aircraft.isValid) return false
        val direct = Geo.distance(origin.coordinate, destination.coordinate)
        val viaAircraft = Geo.distance(origin.coordinate, aircraft) + Geo.distance(aircraft, destination.coordinate)
        return viaAircraft <= direct * 1.25 + 300_000
    }
}

private val Coordinate.isValid: Boolean
    get() = latitude in -90.0..90.0 && longitude in -180.0..180.0

/**
 * Great-circle geometry on a sphere. iOS measures on the WGS 84 ellipsoid
 * through `CLLocation`; the difference (under 0.5%) doesn't affect the
 * plausibility check or the rounded distances shown.
 */
object Geo {
    private const val EARTH_RADIUS_METRES = 6_371_008.8

    fun distance(from: Coordinate, to: Coordinate): Double {
        val lat1 = Math.toRadians(from.latitude)
        val lat2 = Math.toRadians(to.latitude)
        val dLat = lat2 - lat1
        val dLon = Math.toRadians(to.longitude - from.longitude)
        val a = sin(dLat / 2).pow(2) + cos(lat1) * cos(lat2) * sin(dLon / 2).pow(2)
        return 2 * EARTH_RADIUS_METRES * asin(sqrt(a.coerceIn(0.0, 1.0)))
    }

    /** Points along the great circle from [from] to [to], both included, like MapKit's geodesic polyline. */
    fun greatCircle(from: Coordinate, to: Coordinate, segments: Int): List<Coordinate> {
        val lat1 = Math.toRadians(from.latitude)
        val lon1 = Math.toRadians(from.longitude)
        val lat2 = Math.toRadians(to.latitude)
        val lon2 = Math.toRadians(to.longitude)
        val angle = distance(from, to) / EARTH_RADIUS_METRES
        if (angle == 0.0) return listOf(from, to)
        return (0..segments).map { step ->
            val fraction = step.toDouble() / segments
            val a = sin((1 - fraction) * angle) / sin(angle)
            val b = sin(fraction * angle) / sin(angle)
            val x = a * cos(lat1) * cos(lon1) + b * cos(lat2) * cos(lon2)
            val y = a * cos(lat1) * sin(lon1) + b * cos(lat2) * sin(lon2)
            val z = a * sin(lat1) + b * sin(lat2)
            Coordinate(Math.toDegrees(atan2(z, sqrt(x * x + y * y))), Math.toDegrees(atan2(y, x)))
        }
    }
}

interface FlightDetailsService {
    /** Registration details, or null if adsbdb doesn't know the aircraft. */
    suspend fun getAircraft(icao24: String): AircraftInfo?

    /** Scheduled route, or null if adsbdb doesn't know the callsign. */
    suspend fun getRoute(callsign: String): FlightRoute?
}

/**
 * Aircraft and route details from adsbdb.com, a free, community-maintained
 * database that needs no API key. Answers, including "unknown", are cached for
 * the session, since they don't change while a flight is in the air.
 */
@Singleton
class AdsbdbFlightDetailsService @Inject constructor(
    private val networkService: NetworkService,
    private val json: Json,
) : FlightDetailsService {

    @Serializable
    private data class Response<T>(val response: T)

    @Serializable
    private data class AircraftBody(val aircraft: AircraftInfo)

    @Serializable
    private data class RouteBody(val flightroute: FlightRoute)

    private val mutex = Mutex()
    private val aircraftCache = mutableMapOf<String, AircraftInfo?>()
    private val routeCache = mutableMapOf<String, FlightRoute?>()

    override suspend fun getAircraft(icao24: String): AircraftInfo? {
        val key = icao24.lowercase()
        if (!isSafePathComponent(key)) return null
        mutex.withLock { if (key in aircraftCache) return aircraftCache[key] }
        val aircraft = fetch("aircraft/$key", Response.serializer(AircraftBody.serializer()))?.aircraft
        mutex.withLock { aircraftCache[key] = aircraft }
        return aircraft
    }

    override suspend fun getRoute(callsign: String): FlightRoute? {
        val key = callsign.trim().uppercase()
        if (!isSafePathComponent(key)) return null
        mutex.withLock { if (key in routeCache) return routeCache[key] }
        val route = fetch("callsign/$key", Response.serializer(RouteBody.serializer()))?.flightroute
        mutex.withLock { routeCache[key] = route }
        return route
    }

    /** The decoded body, or null when adsbdb answers 404 ("unknown aircraft" / "unknown callsign"). */
    private suspend fun <T> fetch(path: String, serializer: KSerializer<Response<T>>): T? = try {
        json.decodeFromString(serializer, networkService.send(Request.Builder().url("$ROOT_URL/$path").build()).decodeToString()).response
    } catch (error: HttpError.InvalidStatus) {
        if (error.code == 404) null else throw error
    }

    private companion object {
        const val ROOT_URL = "https://api.adsbdb.com/v0"

        fun isSafePathComponent(value: String) = value.isNotEmpty() && value.all { it in 'a'..'z' || it in 'A'..'Z' || it in '0'..'9' }
    }
}
