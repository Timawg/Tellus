package com.pathos.tellus.guide.weather

import com.pathos.tellus.core.network.NetworkService
import com.pathos.tellus.countries.Country
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.Json
import okhttp3.CacheControl
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.Request
import java.io.IOException
import java.time.Clock
import java.time.Duration
import java.time.Instant
import java.util.Locale
import javax.inject.Inject
import javax.inject.Singleton

interface WeatherService {
    suspend fun getWeather(country: Country): DestinationWeather
}

/**
 * Weather at a country's capital from Open-Meteo, which needs no API key.
 * Capitals are located with Open-Meteo's geocoding API; when that fails, the
 * country's centre is used. Locations are cached for the session and
 * forecasts for 15 minutes, as in iOS `WeatherService`.
 */
@Singleton
class OpenMeteoWeatherService @Inject constructor(
    private val networkService: NetworkService,
    private val json: Json,
    private val clock: Clock,
) : WeatherService {

    private data class Location(val name: String, val latitude: Double, val longitude: Double)

    private val mutex = Mutex()
    private val locations = mutableMapOf<String, Location>()
    private val forecasts = mutableMapOf<String, Pair<Instant, DestinationWeather>>()

    override suspend fun getWeather(country: Country): DestinationWeather {
        val location = location(country)
        val key = coordinateText(location.latitude) + "," + coordinateText(location.longitude)
        mutex.withLock { forecasts[key] }?.let { (fetched, weather) ->
            if (Duration.between(fetched, clock.instant()) < FORECAST_LIFETIME) return weather
        }
        val url = "$ROOT_URL/forecast".toHttpUrl().newBuilder()
            .addQueryParameter("latitude", coordinateText(location.latitude))
            .addQueryParameter("longitude", coordinateText(location.longitude))
            .addQueryParameter("current", "temperature_2m,apparent_temperature,weather_code,is_day,wind_speed_10m,relative_humidity_2m")
            .addQueryParameter("daily", "weather_code,temperature_2m_max,temperature_2m_min")
            .addQueryParameter("timezone", "auto")
            .addQueryParameter("forecast_days", "4")
            .build()
        // Forecasts change; this service keeps its own short cache instead.
        val forecast = json.decodeFromString<WeatherForecast>(send(url, CacheControl.FORCE_NETWORK))
        val weather = DestinationWeather.from(location.name, forecast)
        mutex.withLock { forecasts[key] = clock.instant() to weather }
        return weather
    }

    private suspend fun location(country: Country): Location {
        val key = country.cca2 ?: country.name?.common.orEmpty()
        mutex.withLock { locations[key] }?.let { return it }
        var location: Location? = null
        val capital = country.capital?.firstOrNull()
        val code = country.cca2
        if (capital != null && code != null) {
            for (name in searchNames(capital)) {
                location = search(name, code)?.let { Location(capital, it.latitude, it.longitude) }
                if (location != null) break
            }
        }
        if (location == null && country.latlng.size == 2) {
            location = Location(country.name?.common.orEmpty(), country.latlng[0], country.latlng[1])
        }
        if (location == null) throw IOException("No location for ${country.cca3}")
        mutex.withLock { locations[key] = location }
        return location
    }

    /**
     * The best populated place with this name: the capital if it's tagged as
     * one, otherwise the first town or city. Airports and other features
     * sharing the name are ignored.
     */
    private suspend fun search(name: String, countryCode: String): GeocodingResult.Place? {
        val url = "$GEOCODING_ROOT_URL/search".toHttpUrl().newBuilder()
            .addQueryParameter("name", name)
            .addQueryParameter("countryCode", countryCode)
            .addQueryParameter("count", "10")
            .build()
        val places = json.decodeFromString<GeocodingResult>(send(url, null)).results.orEmpty()
        return places.firstOrNull { it.featureCode == "PPLC" } ?: places.firstOrNull { it.isPopulatedPlace }
    }

    private suspend fun send(url: HttpUrl, cacheControl: CacheControl?): String {
        val request = Request.Builder().url(url).apply { cacheControl?.let(::cacheControl) }.build()
        return networkService.send(request).decodeToString()
    }

    companion object {
        private const val ROOT_URL = "https://api.open-meteo.com/v1"
        private const val GEOCODING_ROOT_URL = "https://geocoding-api.open-meteo.com/v1"
        private val FORECAST_LIFETIME = Duration.ofMinutes(15)

        private fun coordinateText(value: Double) = String.format(Locale.ROOT, "%.3f", value)

        /**
         * Spellings to try for a capital. The dataset sometimes uses long
         * official names ("City of San Marino") or apostrophes the geocoder
         * doesn't match ("Sana'a" only finds the airport; "Sanaa" finds the city).
         */
        fun searchNames(capital: String): List<String> {
            val names = mutableListOf(capital)
            for (prefix in listOf("City of ", "South ")) {
                if (capital.startsWith(prefix)) names += capital.removePrefix(prefix)
            }
            for (name in names.toList()) {
                if (name.any { it in "'’" }) names += name.filterNot { it in "'’" }
            }
            return names
        }
    }
}
