package com.pathos.tellus.guide.profile

import android.icu.text.CompactDecimalFormat
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.pathos.tellus.guide.GuideSection
import com.pathos.tellus.guide.LabeledRow
import com.pathos.tellus.guide.LoadState
import com.pathos.tellus.guide.LoadingRow
import com.pathos.tellus.guide.RetryButton
import com.pathos.tellus.guide.SecondaryText
import com.pathos.tellus.guide.SourceLink
import com.pathos.tellus.guide.rememberLoad
import java.math.MathContext
import java.text.NumberFormat
import java.util.Locale

/** World Bank indicators grouped by category, as in iOS `CountryProfileSections`. */
@Composable
fun CountryProfileSections(countryCode: String?, load: suspend (String) -> List<CountryIndicatorObservation>) {
    val (state, retry) = rememberLoad(countryCode) { load(countryCode.orEmpty()) }
    when (state) {
        is LoadState.Loaded -> {
            val observations = state.value
            if (observations.isEmpty()) {
                GuideSection("Country profile") {
                    SecondaryText("No country indicators are available from the World Bank.")
                }
            }
            CountryIndicator.Category.entries.forEach { category ->
                val rows = observations.filter { it.indicator.category == category }
                if (rows.isNotEmpty()) {
                    GuideSection(category.title) {
                        rows.forEach { ObservationRow(it, countryCode) }
                    }
                }
            }
        }
        LoadState.Failed -> GuideSection("Country profile") {
            SecondaryText("Couldn't load country indicators.")
            RetryButton(retry)
        }
        LoadState.Loading -> GuideSection("Country profile") {
            LoadingRow("Loading country indicators…")
        }
    }
}

@Composable
private fun ObservationRow(row: CountryIndicatorObservation, countryCode: String?) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        LabeledRow(row.indicator.title, formatIndicatorValue(row, Locale.getDefault()))
        if (countryCode != null) {
            SourceLink(
                title = "World Bank · ${row.year}",
                url = "https://data.worldbank.org/indicator/${row.indicator.code}?locations=$countryCode",
                modifier = Modifier.semantics {
                    contentDescription = "${row.indicator.title}, World Bank, observation year ${row.year}"
                },
            )
        }
    }
}

private fun formatIndicatorValue(row: CountryIndicatorObservation, locale: Locale): String = when (row.indicator) {
    CountryIndicator.POPULATION -> NumberFormat.getIntegerInstance(locale).format(row.value)
    CountryIndicator.GDP -> CompactDecimalFormat.getInstance(locale, CompactDecimalFormat.CompactStyle.LONG)
        .apply { maximumSignificantDigits = 3 }
        .format(row.value.toBigDecimal().round(MathContext(3))) + " USD"
    CountryIndicator.GDP_PER_CAPITA -> "USD " + NumberFormat.getIntegerInstance(locale).format(row.value)
    CountryIndicator.SURFACE_AREA -> NumberFormat.getNumberInstance(locale)
        .apply { maximumFractionDigits = 1 }
        .format(row.value) + " km²"
    CountryIndicator.INTERNET_USE, CountryIndicator.ELECTRICITY_ACCESS -> NumberFormat.getPercentInstance(locale)
        .apply { maximumFractionDigits = 1 }
        .format(row.value / 100)
}
