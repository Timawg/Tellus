package com.pathos.tellus.guide.weather

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.time.DateTimeException
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeParseException

/** Open-Meteo forecast response. */
@Serializable
data class WeatherForecast(
    @SerialName("utc_offset_seconds") val utcOffsetSeconds: Int,
    val timezone: String,
    val current: Current,
    val daily: Daily,
) {
    @Serializable
    data class Current(
        @SerialName("temperature_2m") val temperature: Double,
        @SerialName("apparent_temperature") val apparentTemperature: Double,
        @SerialName("weather_code") val weatherCode: Int,
        @SerialName("is_day") val isDay: Int,
        @SerialName("wind_speed_10m") val windSpeed: Double,
        @SerialName("relative_humidity_2m") val relativeHumidity: Int,
    )

    @Serializable
    data class Daily(
        val time: List<String>,
        @SerialName("weather_code") val weatherCode: List<Int>,
        @SerialName("temperature_2m_max") val temperatureMax: List<Double>,
        @SerialName("temperature_2m_min") val temperatureMin: List<Double>,
    )
}

/** Open-Meteo geocoding response. */
@Serializable
data class GeocodingResult(val results: List<Place>? = null) {
    @Serializable
    data class Place(
        val name: String,
        val latitude: Double,
        val longitude: Double,
        /** GeoNames feature code: "PPLC" for a capital, "PPL…" for other populated places, "AIRP" for airports. */
        @SerialName("feature_code") val featureCode: String? = null,
    ) {
        val isPopulatedPlace: Boolean get() = featureCode?.startsWith("PPL") == true
    }
}

/** Current weather and the next few days at a destination's capital. */
data class DestinationWeather(
    /** Where the weather is for: the capital, or the country itself when the capital couldn't be located. */
    val placeName: String,
    val zone: ZoneId,
    val condition: WeatherCondition,
    val isDay: Boolean,
    /** Degrees Celsius. */
    val temperature: Double,
    val feelsLike: Double,
    /** Kilometres per hour. */
    val windSpeed: Double,
    val humidity: Int,
    val days: List<Day>,
) {
    data class Day(val date: LocalDate, val condition: WeatherCondition, val high: Double, val low: Double)

    companion object {
        fun from(placeName: String, forecast: WeatherForecast): DestinationWeather {
            val zone = try {
                ZoneId.of(forecast.timezone)
            } catch (_: DateTimeException) {
                try {
                    ZoneOffset.ofTotalSeconds(forecast.utcOffsetSeconds)
                } catch (_: DateTimeException) {
                    ZoneId.systemDefault()
                }
            }
            val daily = forecast.daily
            // The arrays should match, but only read as far as the shortest.
            val count = minOf(daily.time.size, daily.weatherCode.size, daily.temperatureMax.size, daily.temperatureMin.size)
            val days = (0 until count).mapNotNull { index ->
                val date = try {
                    LocalDate.parse(daily.time[index])
                } catch (_: DateTimeParseException) {
                    return@mapNotNull null
                }
                Day(date, WeatherCondition.of(daily.weatherCode[index]), daily.temperatureMax[index], daily.temperatureMin[index])
            }
            val current = forecast.current
            return DestinationWeather(
                placeName = placeName,
                zone = zone,
                condition = WeatherCondition.of(current.weatherCode),
                isDay = current.isDay == 1,
                temperature = current.temperature,
                feelsLike = current.apparentTemperature,
                windSpeed = current.windSpeed,
                humidity = current.relativeHumidity,
                days = days,
            )
        }
    }
}

/** WMO weather interpretation codes, as used by Open-Meteo, grouped into what a traveller cares about. */
enum class WeatherCondition(val description: String) {
    CLEAR("Clear"),
    PARTLY_CLOUDY("Partly cloudy"),
    OVERCAST("Cloudy"),
    FOG("Fog"),
    DRIZZLE("Drizzle"),
    RAIN("Rain"),
    HEAVY_RAIN("Heavy rain"),
    FREEZING_RAIN("Freezing rain"),
    SNOW("Snow"),
    SHOWERS("Showers"),
    THUNDERSTORM("Thunderstorms"),
    UNKNOWN("Unknown");

    /** An emoji standing in for the iOS SF Symbol, with a night variant where one exists. */
    fun symbol(isDay: Boolean = true): String = when (this) {
        CLEAR -> if (isDay) "☀️" else "🌙"
        PARTLY_CLOUDY -> if (isDay) "⛅" else "☁️"
        OVERCAST -> "☁️"
        FOG -> "🌫️"
        DRIZZLE -> "🌦️"
        RAIN -> "🌧️"
        HEAVY_RAIN -> "🌧️"
        FREEZING_RAIN -> "🌨️"
        SNOW -> "❄️"
        SHOWERS -> if (isDay) "🌦️" else "🌧️"
        THUNDERSTORM -> "⛈️"
        UNKNOWN -> "❔"
    }

    companion object {
        fun of(code: Int): WeatherCondition = when (code) {
            0, 1 -> CLEAR
            2 -> PARTLY_CLOUDY
            3 -> OVERCAST
            45, 48 -> FOG
            in 51..57 -> DRIZZLE
            61, 63 -> RAIN
            65 -> HEAVY_RAIN
            66, 67 -> FREEZING_RAIN
            in 71..77, 85, 86 -> SNOW
            in 80..82 -> SHOWERS
            in 95..99 -> THUNDERSTORM
            else -> UNKNOWN
        }
    }
}
