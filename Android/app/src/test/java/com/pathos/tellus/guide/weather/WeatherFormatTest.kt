package com.pathos.tellus.guide.weather

import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale

class WeatherFormatTest {

    private val metric = WeatherFormat(Locale.UK, usesFahrenheit = false, usesMph = false)
    private val us = WeatherFormat(Locale.US, usesFahrenheit = true, usesMph = true)

    @Test
    fun temperatureInUsersUnit() {
        assertEquals("8°", metric.temperature(8.4))
        assertEquals("47°", us.temperature(8.4))
        assertEquals("-3°", metric.temperature(-2.6))
    }

    @Test
    fun windInUsersUnit() {
        assertEquals("12 km/h", metric.wind(12.3))
        assertEquals("8 mph", us.wind(12.3))
    }

    @Test
    fun mphRegions() {
        assertEquals(true, WeatherFormat.usesMph(Locale.US))
        assertEquals(true, WeatherFormat.usesMph(Locale.UK))
        assertEquals(false, WeatherFormat.usesMph(Locale.GERMANY))
    }

    @Test
    fun dayNamesAreInDestinationTimeZone() {
        // 23:30 UTC is already the next day in Tokyo.
        val now = Instant.parse("2026-11-13T23:30:00Z")
        val tokyo = ZoneId.of("Asia/Tokyo")
        assertEquals("Today", metric.dayName(LocalDate.of(2026, 11, 14), now, tokyo))
        assertEquals("Friday", metric.dayName(LocalDate.of(2026, 11, 13), now, tokyo))
        assertEquals("08:30", metric.localTime(now, tokyo))
    }
}
