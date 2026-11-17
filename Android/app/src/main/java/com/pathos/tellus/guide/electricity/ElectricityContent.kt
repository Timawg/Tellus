package com.pathos.tellus.guide.electricity

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.dp
import com.pathos.tellus.guide.GuideSection
import com.pathos.tellus.guide.LabeledRow
import com.pathos.tellus.guide.LoadState
import com.pathos.tellus.guide.LoadingRow
import com.pathos.tellus.guide.RetryButton
import com.pathos.tellus.guide.SecondaryText
import com.pathos.tellus.guide.SourceLink
import com.pathos.tellus.guide.rememberLoad
import java.text.NumberFormat
import kotlin.math.abs

/** Ember's yearly generation mix for a country, as in iOS `CountryElectricityView`. */
@Composable
fun ElectricityContent(countryCode: String, countryName: String, load: suspend (String) -> CountryElectricityProfile?) {
    val (state, retry) = rememberLoad(countryCode) { load(countryCode) }
    Column {
        when (state) {
            is LoadState.Loaded -> {
                val profile = state.value
                if (profile == null) {
                    GuideSection("No electricity data") {
                        SecondaryText("Ember has no yearly electricity profile for this country.")
                    }
                } else {
                    Summary(countryName, profile)
                    GenerationMix(profile)
                }
            }
            LoadState.Failed -> GuideSection(null) {
                SecondaryText("Couldn't load electricity data.")
                RetryButton(retry)
            }
            LoadState.Loading -> GuideSection(null) { LoadingRow("Loading electricity data…") }
        }
        GuideSection(header = null, footer = { Text("Source: Ember, CC BY 4.0") }) {
            SourceLink("Ember Yearly Electricity Data", CountryElectricityProfile.SOURCE_URL)
        }
    }
}

@Composable
private fun Summary(countryName: String, profile: CountryElectricityProfile) {
    GuideSection(countryName) {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            LabeledRow("Domestic generation", terawattHours(profile.totalGenerationTWh))
            Observation(profile.year)
        }
        profile.netImportsTWh?.let { netImports ->
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                LabeledRow(if (netImports < 0) "Net exports" else "Net imports", terawattHours(abs(netImports)))
                Observation(profile.year)
            }
        }
    }
}

@Composable
private fun GenerationMix(profile: CountryElectricityProfile) {
    GuideSection("Generation by source") {
        if (profile.fuels.isEmpty()) {
            SecondaryText(
                if (profile.totalGenerationTWh == 0.0) "Ember reports zero domestic generation for this year."
                else "Ember has no breakdown by source for this year.",
            )
        }
        profile.fuels.forEach { fuel ->
            Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
                LabeledRow(fuel.name, terawattHours(fuel.generationTWh))
                fuel.sharePercent?.let { share ->
                    LinearProgressIndicator(
                        progress = { (share / 100).toFloat().coerceIn(0f, 1f) },
                        modifier = Modifier
                            .fillMaxWidth()
                            .clearAndSetSemantics { },
                    )
                    val percent = NumberFormat.getPercentInstance().apply { maximumFractionDigits = 3 }.format(share / 100)
                    Text("$percent of domestic generation", style = MaterialTheme.typography.bodyMedium)
                }
                Observation(profile.year)
            }
        }
    }
}

@Composable
private fun Observation(year: Int) {
    Text("Ember · $year", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
}

private fun terawattHours(value: Double): String =
    NumberFormat.getNumberInstance().apply { maximumFractionDigits = 3 }.format(value) + " TWh"
