package com.pathos.tellus.guide.weather

import java.text.NumberFormat
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.time.format.TextStyle
import java.util.Locale
import kotlin.math.roundToInt

/**
 * Weather text in the user's units. iOS picks units from the device region
 * through `Measurement`; [usesFahrenheit] and [usesMph] carry that choice in,
 * so the formatting itself stays deterministic.
 */
data class WeatherFormat(val locale: Locale, val usesFahrenheit: Boolean, val usesMph: Boolean) {

    /** "10°". */
    fun temperature(celsius: Double): String {
        val value = if (usesFahrenheit) celsius * 9 / 5 + 32 else celsius
        return NumberFormat.getIntegerInstance(locale).format(value.roundToInt()) + "°"
    }

    /** "5 km/h" or "3 mph". */
    fun wind(kilometresPerHour: Double): String {
        val value = if (usesMph) kilometresPerHour / 1.609344 else kilometresPerHour
        return NumberFormat.getIntegerInstance(locale).format(value.roundToInt()) + if (usesMph) " mph" else " km/h"
    }

    /** "16:01" at the destination. */
    fun localTime(now: Instant, zone: ZoneId): String =
        DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withLocale(locale).withZone(zone).format(now)

    /** "Today", then weekday names ("Thursday"), in the destination's time zone. */
    fun dayName(date: LocalDate, now: Instant, zone: ZoneId): String =
        if (date == now.atZone(zone).toLocalDate()) "Today" else date.dayOfWeek.getDisplayName(TextStyle.FULL, locale)

    companion object {
        /** Regions where wind is given in miles per hour, matching Foundation's `.wind` usage. */
        private val mphRegions = setOf("US", "GB", "LR", "MM")

        fun usesMph(locale: Locale) = locale.country in mphRegions
    }
}
