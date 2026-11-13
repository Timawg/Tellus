package com.pathos.tellus.guide.weather

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.width
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.os.ConfigurationCompat
import androidx.core.text.util.LocalePreferences
import com.pathos.tellus.guide.GuideSection
import com.pathos.tellus.guide.LabeledRow
import kotlinx.coroutines.delay
import java.time.Instant
import java.util.Locale

/** The user's weather units, read from the device's region and unit preference. */
@Composable
fun rememberWeatherFormat(): WeatherFormat {
    val configuration = LocalConfiguration.current
    return remember(configuration) {
        val locale = ConfigurationCompat.getLocales(configuration)[0] ?: Locale.getDefault()
        WeatherFormat(
            locale = locale,
            usesFahrenheit = LocalePreferences.getTemperatureUnit(locale) == LocalePreferences.TemperatureUnit.FAHRENHEIT,
            usesMph = WeatherFormat.usesMph(locale),
        )
    }
}

/** The current time, updated at the start of every minute, for local-time labels. */
@Composable
fun rememberMinuteTicker(): Instant {
    val now by produceState(Instant.now()) {
        while (true) {
            val current = Instant.now()
            value = current
            delay(60_000 - current.toEpochMilli() % 60_000)
        }
    }
    return now
}

/** Current weather, local time and the next days at the capital, as in iOS `DestinationWeatherSection`. */
@Composable
fun WeatherSection(weather: DestinationWeather) {
    val format = rememberWeatherFormat()
    val now = rememberMinuteTicker()
    GuideSection(
        header = "Weather in ${weather.placeName}",
        footer = { Text("Weather data by Open-Meteo.com") },
    ) {
        val summary = "${weather.condition.description}, ${format.temperature(weather.temperature)}"
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clearAndSetSemantics {
                    contentDescription = "$summary. Feels like ${format.temperature(weather.feelsLike)}, " +
                        "wind ${format.wind(weather.windSpeed)}, humidity ${weather.humidity}%"
                },
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text(weather.condition.symbol(weather.isDay), style = MaterialTheme.typography.displaySmall)
            Column(Modifier.weight(1f)) {
                Text(format.temperature(weather.temperature), style = MaterialTheme.typography.headlineLarge)
                Text(weather.condition.description, style = MaterialTheme.typography.bodyMedium)
            }
            Column(horizontalAlignment = Alignment.End) {
                val style = MaterialTheme.typography.bodySmall
                val color = MaterialTheme.colorScheme.onSurfaceVariant
                Text("Feels like ${format.temperature(weather.feelsLike)}", style = style, color = color)
                Text("Wind ${format.wind(weather.windSpeed)}", style = style, color = color)
                Text("Humidity ${weather.humidity}%", style = style, color = color)
            }
        }
        LabeledRow("Local time", format.localTime(now, weather.zone))
        weather.days.forEach { day ->
            val range = "${format.temperature(day.low)} – ${format.temperature(day.high)}"
            val name = format.dayName(day.date, now, weather.zone)
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clearAndSetSemantics { contentDescription = "$name, ${day.condition.description}, $range" },
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(name, Modifier.weight(1f))
                Text(day.condition.symbol(), Modifier.width(32.dp), textAlign = TextAlign.Center)
                Text(range, Modifier.weight(1f), textAlign = TextAlign.End)
            }
        }
    }
}
