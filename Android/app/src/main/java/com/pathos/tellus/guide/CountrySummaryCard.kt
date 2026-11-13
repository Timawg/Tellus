package com.pathos.tellus.guide

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Info
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.pathos.tellus.countries.Country
import com.pathos.tellus.countries.FlagImage
import com.pathos.tellus.guide.exchangerates.ExchangeRate
import com.pathos.tellus.guide.weather.DestinationWeather
import com.pathos.tellus.guide.weather.WeatherCondition
import com.pathos.tellus.guide.weather.rememberMinuteTicker
import com.pathos.tellus.guide.weather.rememberWeatherFormat
import com.pathos.tellus.ui.theme.TellusTheme
import java.time.ZoneId

/**
 * The selected country at the top of the map: its name and capital, the
 * weather and local time there, the exchange rate, and the button that opens
 * the guide. Ported from iOS `CountrySummaryView`; the status dots and alert
 * banner arrive with the advisory, outbreak and disaster issues.
 */
@Composable
fun CountrySummaryCard(
    country: Country,
    weather: DestinationWeather?,
    exchangeRate: ExchangeRate?,
    onOpenGuide: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val name = country.name?.common ?: return
    Surface(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        shape = RoundedCornerShape(20.dp),
        color = MaterialTheme.colorScheme.surfaceContainer.copy(alpha = 0.92f),
        tonalElevation = 3.dp,
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 20.dp, vertical = 16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FlagImage(country.flagUrl)
                    Text(name, style = MaterialTheme.typography.titleMedium)
                }
                // City-states such as Singapore would repeat their name.
                val capital = country.capital?.firstOrNull()
                if (capital != null && capital != name) {
                    Text(
                        text = capital,
                        modifier = Modifier.semantics { contentDescription = "Capital: $capital" },
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center,
                    )
                }
            }
            LiveInfoStrip(weather, exchangeRate)
            FilledTonalButton(onClick = onOpenGuide) {
                Icon(Icons.Filled.Info, contentDescription = null)
                Text("Country guide", Modifier.padding(start = 8.dp))
            }
        }
    }
}

/** Weather and local time at the capital, and the exchange rate from the home currency, in one line. */
@Composable
private fun LiveInfoStrip(weather: DestinationWeather?, rate: ExchangeRate?) {
    if (weather == null && rate == null) return
    val format = rememberWeatherFormat()
    val now = rememberMinuteTicker()
    val style = MaterialTheme.typography.labelLarge
    Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
        if (weather != null) {
            val temperature = format.temperature(weather.temperature)
            Text(
                "${weather.condition.symbol(weather.isDay)} $temperature",
                modifier = Modifier.clearAndSetSemantics { contentDescription = "${weather.condition.description}, $temperature" },
                style = style,
            )
            val time = format.localTime(now, weather.zone)
            Text(
                "🕒 $time",
                modifier = Modifier.clearAndSetSemantics { contentDescription = "Local time $time" },
                style = style,
            )
        }
        if (rate != null) {
            val text = "1 ${rate.home} = ${ExchangeRate.format(rate.rate, format.locale)} ${rate.destination}"
            Text(
                "💱 $text",
                modifier = Modifier.clearAndSetSemantics { contentDescription = text },
                style = style,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

private val previewCountry = Country(
    name = Country.Name("Sweden"),
    cca2 = "SE",
    cca3 = "SWE",
    capital = listOf("Stockholm"),
    translations = emptyMap(),
    latlng = listOf(62.0, 15.0),
)

@Preview
@Composable
private fun CountrySummaryCardPreview() {
    TellusTheme {
        CountrySummaryCard(
            country = previewCountry,
            weather = DestinationWeather(
                "Stockholm", ZoneId.of("Europe/Stockholm"), WeatherCondition.PARTLY_CLOUDY, true,
                8.4, 6.0, 12.0, 70, emptyList(),
            ),
            exchangeRate = ExchangeRate("EUR", "SEK", 11.52, "2026-11-13"),
            onOpenGuide = {},
        )
    }
}

@Preview
@Composable
private fun CountrySummaryCardLoadingPreview() {
    TellusTheme {
        CountrySummaryCard(previewCountry, weather = null, exchangeRate = null, onOpenGuide = {})
    }
}
