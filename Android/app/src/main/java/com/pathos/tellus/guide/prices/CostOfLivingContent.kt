package com.pathos.tellus.guide.prices

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuAnchorType
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.pathos.tellus.guide.GuideSection
import com.pathos.tellus.guide.LabeledRow
import com.pathos.tellus.guide.LoadState
import com.pathos.tellus.guide.LoadingRow
import com.pathos.tellus.guide.RetryButton
import com.pathos.tellus.guide.SecondaryText
import com.pathos.tellus.guide.SourceLink
import com.pathos.tellus.guide.rememberLoad
import java.text.NumberFormat
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import kotlin.math.abs

/** Eurostat price levels compared with the EU average or another country, as in iOS `CountryCostOfLivingView`. */
@Composable
fun CostOfLivingContent(countryCode: String, countryName: String, load: suspend () -> EurostatPriceLevels) {
    var referenceCode by rememberSaveable(countryCode) { mutableStateOf(EurostatPriceLevels.EU_AVERAGE_CODE) }
    val (state, retry) = rememberLoad(countryCode) { load() }
    Column {
        when (state) {
            is LoadState.Loaded -> {
                val levels = state.value
                val comparison = levels.comparison(countryCode, referenceCode)
                if (comparison == null) {
                    GuideSection("No comparable prices") {
                        SecondaryText("Eurostat has no comparable household price data for this selection.")
                    }
                } else {
                    ComparisonSections(
                        countryName = countryName,
                        comparison = comparison,
                        referenceAreas = levels.referenceAreas(countryCode),
                        referenceCode = referenceCode,
                        onReferenceChange = { referenceCode = it },
                    )
                }
                val accessed = DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM)
                    .withZone(ZoneId.systemDefault())
                    .format(levels.accessedAt)
                GuideSection(
                    header = null,
                    footer = {
                        Text(
                            if (levels.isStale) "Refresh unavailable. Showing Eurostat data accessed $accessed."
                            else "Eurostat data accessed $accessed.",
                        )
                    },
                ) {
                    SourceLink("Eurostat price level data", EurostatPriceLevels.SOURCE_URL)
                }
            }
            LoadState.Failed -> GuideSection(null) {
                SecondaryText("Couldn't load Eurostat prices.")
                RetryButton(retry)
            }
            LoadState.Loading -> GuideSection(null) { LoadingRow("Loading Eurostat prices…") }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ComparisonSections(
    countryName: String,
    comparison: EurostatPriceLevels.Comparison,
    referenceAreas: List<EurostatPriceLevels.Area>,
    referenceCode: String,
    onReferenceChange: (String) -> Unit,
) {
    GuideSection(
        header = countryName,
        footer = { Text("Eurostat · ${comparison.year}. National price levels for comparable goods and services.") },
    ) {
        var expanded by rememberSaveable { mutableStateOf(false) }
        ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = { expanded = it }) {
            TextField(
                value = referenceAreas.firstOrNull { it.id == referenceCode }?.name ?: referenceCode,
                onValueChange = {},
                readOnly = true,
                label = { Text("Compare with") },
                trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded) },
                modifier = Modifier
                    .fillMaxWidth()
                    .menuAnchor(ExposedDropdownMenuAnchorType.PrimaryNotEditable),
            )
            ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                referenceAreas.forEach { area ->
                    DropdownMenuItem(
                        text = { Text(area.name) },
                        onClick = {
                            onReferenceChange(area.id)
                            expanded = false
                        },
                    )
                }
            }
        }
        PriceRow(EurostatPriceLevels.Category.OVERALL, comparison)
    }
    val categories = EurostatPriceLevels.Category.entries.filter { it != EurostatPriceLevels.Category.OVERALL }
    GuideSection("Prices by category") {
        if (categories.any { it in comparison.changes }) {
            categories.forEach { PriceRow(it, comparison) }
        } else {
            SecondaryText("Eurostat has no category breakdown for this comparison.")
        }
    }
}

@Composable
private fun PriceRow(category: EurostatPriceLevels.Category, comparison: EurostatPriceLevels.Comparison) {
    LabeledRow(category.title, comparison.changes[category]?.let(::priceDifference) ?: "Unavailable")
}

/** "12% higher", "3.5% lower", or "About the same" within a twentieth of a percent. */
fun priceDifference(change: Double, format: NumberFormat = NumberFormat.getPercentInstance()): String {
    if (abs(change) < 0.0005) return "About the same"
    format.maximumFractionDigits = 1
    val percent = format.format(abs(change))
    return if (change > 0) "$percent higher" else "$percent lower"
}
