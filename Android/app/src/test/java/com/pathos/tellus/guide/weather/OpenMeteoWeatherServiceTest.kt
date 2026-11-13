package com.pathos.tellus.guide.weather

import com.pathos.tellus.countries.Country
import com.pathos.tellus.testing.FakeNetworkService
import com.pathos.tellus.testing.MutableClock
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import okhttp3.CacheControl
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Duration
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset

class OpenMeteoWeatherServiceTest {

    private val json = Json { ignoreUnknownKeys = true }
    private val clock = MutableClock()

    private fun forecast(timezone: String = "Europe/Stockholm") = """
        {"utc_offset_seconds":3600,"timezone":"$timezone",
         "current":{"temperature_2m":8.4,"apparent_temperature":6.1,"weather_code":2,"is_day":1,"wind_speed_10m":12.3,"relative_humidity_2m":71},
         "daily":{"time":["2026-11-13","2026-11-14","bad-date"],"weather_code":[3,61,0],"temperature_2m_max":[9.0,7.5,6.0],"temperature_2m_min":[2.0,1.5]},
         "extra":true}
    """.trimIndent()

    private val sweden = Country(
        name = Country.Name("Sweden"), cca2 = "SE", capital = listOf("Stockholm"),
        translations = emptyMap(), latlng = listOf(62.0, 15.0),
    )

    @Test
    fun usesCapitalTaggedAsCapitalOverAirport() = runTest {
        val network = FakeNetworkService(
            mapOf(
                "geocoding-api" to {
                    """{"results":[{"name":"Stockholm Arlanda","latitude":59.65,"longitude":17.93,"feature_code":"AIRP"},
                       {"name":"Stockholm","latitude":59.329,"longitude":18.069,"feature_code":"PPLC"}]}"""
                },
                "api.open-meteo.com" to { forecast() },
            ),
        )
        val weather = OpenMeteoWeatherService(network, json, clock).getWeather(sweden)

        val forecastRequest = network.requests.last()
        assertEquals("59.329", forecastRequest.url.queryParameter("latitude"))
        assertEquals("18.069", forecastRequest.url.queryParameter("longitude"))
        assertEquals(CacheControl.FORCE_NETWORK.toString(), forecastRequest.cacheControl.toString())
        assertEquals("Stockholm", weather.placeName)
        assertEquals(WeatherCondition.PARTLY_CLOUDY, weather.condition)
        assertEquals(ZoneId.of("Europe/Stockholm"), weather.zone)
        // Only as many days as the shortest array, and unparseable dates are dropped.
        assertEquals(listOf(LocalDate.of(2026, 11, 13), LocalDate.of(2026, 11, 14)), weather.days.map { it.date })
    }

    @Test
    fun fallsBackToCountryCentreWithoutCapitalMatch() = runTest {
        val network = FakeNetworkService(
            mapOf(
                "geocoding-api" to { """{"results":[{"name":"Stockholm","latitude":1.0,"longitude":1.0,"feature_code":"AIRP"}]}""" },
                "api.open-meteo.com" to { forecast() },
            ),
        )
        val weather = OpenMeteoWeatherService(network, json, clock).getWeather(sweden)

        assertEquals("Sweden", weather.placeName)
        assertEquals("62.000", network.requests.last().url.queryParameter("latitude"))
    }

    @Test
    fun cachesForecastForFifteenMinutesAndLocationForSession() = runTest {
        val network = FakeNetworkService(
            mapOf(
                "geocoding-api" to { """{"results":[{"name":"Stockholm","latitude":59.3,"longitude":18.1,"feature_code":"PPLC"}]}""" },
                "api.open-meteo.com" to { forecast() },
            ),
        )
        val service = OpenMeteoWeatherService(network, json, clock)
        service.getWeather(sweden)
        clock.now = clock.now.plus(Duration.ofMinutes(14))
        service.getWeather(sweden)
        assertEquals(1, network.count("/forecast"))

        clock.now = clock.now.plus(Duration.ofMinutes(2))
        service.getWeather(sweden)
        assertEquals(2, network.count("/forecast"))
        assertEquals(1, network.count("/search"))
    }

    @Test
    fun unknownTimezoneFallsBackToOffset() {
        val weather = DestinationWeather.from("X", json.decodeFromString(forecast(timezone = "Not/AZone")))
        assertEquals(ZoneOffset.ofHours(1), weather.zone)
    }

    @Test
    fun searchNamesTryShorterAndApostropheFreeSpellings() {
        assertEquals(listOf("City of San Marino", "San Marino"), OpenMeteoWeatherService.searchNames("City of San Marino"))
        assertEquals(listOf("Sana'a", "Sanaa"), OpenMeteoWeatherService.searchNames("Sana'a"))
        assertEquals(listOf("Stockholm"), OpenMeteoWeatherService.searchNames("Stockholm"))
    }

    @Test
    fun weatherCodesGroupLikeIos() {
        val expected = mapOf(
            0 to WeatherCondition.CLEAR, 2 to WeatherCondition.PARTLY_CLOUDY, 48 to WeatherCondition.FOG,
            55 to WeatherCondition.DRIZZLE, 65 to WeatherCondition.HEAVY_RAIN, 77 to WeatherCondition.SNOW,
            86 to WeatherCondition.SNOW, 81 to WeatherCondition.SHOWERS, 99 to WeatherCondition.THUNDERSTORM,
            4 to WeatherCondition.UNKNOWN,
        )
        expected.forEach { (code, condition) -> assertEquals("code $code", condition, WeatherCondition.of(code)) }
        assertTrue(WeatherCondition.CLEAR.symbol(isDay = false) != WeatherCondition.CLEAR.symbol(isDay = true))
    }
}
