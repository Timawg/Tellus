package com.pathos.tellus.guide.democracy

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.pathos.tellus.guide.GuideSection
import com.pathos.tellus.guide.LabeledRow
import com.pathos.tellus.guide.LoadState
import com.pathos.tellus.guide.LoadingRow
import com.pathos.tellus.guide.RetryButton
import com.pathos.tellus.guide.SecondaryText
import com.pathos.tellus.guide.SourceLink
import com.pathos.tellus.guide.profile.AnnualObservation
import com.pathos.tellus.guide.rememberLoad
import com.pathos.tellus.ui.theme.TellusTheme
import java.util.Locale
import kotlin.math.ceil

/** V-Dem democracy and UNODC homicide trends, as in iOS `DemocracySafetyView`. */
@Composable
fun DemocracySafetyContent(
    cca3: String?,
    cca2: String?,
    loadDemocracy: suspend (String?) -> DemocracyProfile,
    loadHomicides: suspend (String) -> List<AnnualObservation>,
) {
    Column {
        val (democracy, _) = rememberLoad(cca3) { loadDemocracy(cca3) }
        DemocracySection(democracy)
        val (homicides, retry) = rememberLoad(cca2) { cca2?.let { loadHomicides(it) }.orEmpty() }
        HomicideSection(homicides, retry)
    }
}

@Composable
private fun DemocracySection(state: LoadState<DemocracyProfile>) {
    GuideSection(
        header = "Democracy",
        footer = {
            Text("V-Dem’s index covers election quality, voting rights, and freedom of expression and association.")
            if (state is LoadState.Loaded) {
                SourceLink("V-Dem Country-Year Dataset v${state.value.version}", "https://v-dem.net/data/dataset-archive/")
                Text("Adapted from the full dataset using the ten most recent years.")
                SourceLink("CC BY-SA 4.0", "https://creativecommons.org/licenses/by-sa/4.0/")
            }
        },
    ) {
        when (state) {
            is LoadState.Loaded -> {
                val series = state.value.series
                if (series.isEmpty()) {
                    SecondaryText("V-Dem has no observations for this destination in the bundled release.")
                }
                series.forEach { item ->
                    val latest = item.observations.lastOrNull() ?: return@forEach
                    LabeledRow(item.area ?: "Electoral Democracy Index", String.format(Locale.getDefault(), "%.3f / 1", latest.value))
                    ObservationYear(latest.year)
                    AnnualObservationChart(item.observations, "Electoral Democracy Index", upperBound = 1.0, decimals = 3)
                }
            }
            LoadState.Failed -> SecondaryText("Couldn’t load the bundled V-Dem data.")
            LoadState.Loading -> LoadingRow("Loading democracy data…")
        }
    }
}

@Composable
private fun HomicideSection(state: LoadState<List<AnnualObservation>>, retry: () -> Unit) {
    val metric = "Intentional homicides per 100,000 people"
    GuideSection(
        header = "Public safety",
        footer = {
            Text("Up to ten years of reported data.")
            SourceLink("UNODC via World Bank World Development Indicators", "https://data.worldbank.org/indicator/VC.IHR.PSRC.P5")
            SourceLink("CC BY 4.0", "https://creativecommons.org/licenses/by/4.0/")
        },
    ) {
        when (state) {
            is LoadState.Loaded -> {
                val observations = state.value
                val latest = observations.lastOrNull()
                if (latest == null) {
                    SecondaryText("No homicide observations are available for this destination.")
                } else {
                    LabeledRow(metric, String.format(Locale.getDefault(), "%.2f", latest.value))
                    ObservationYear(latest.year)
                    AnnualObservationChart(
                        observations = observations,
                        metric = metric,
                        upperBound = maxOf(1.0, ceil(observations.maxOf { it.value })),
                        decimals = 2,
                    )
                }
            }
            LoadState.Failed -> {
                SecondaryText("Couldn’t load homicide statistics.")
                RetryButton(retry)
            }
            LoadState.Loading -> LoadingRow("Loading homicide statistics…")
        }
    }
}

@Composable
private fun ObservationYear(year: Int) {
    Text(
        "Observation year $year",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

/**
 * Yearly values as points on a 0…[upperBound] scale, with gaps between years
 * proportional to time, like the iOS Swift Charts point chart. Only drawn when
 * there's more than one year. TalkBack reads the values as a list.
 */
@Composable
private fun AnnualObservationChart(observations: List<AnnualObservation>, metric: String, upperBound: Double, decimals: Int) {
    val firstYear = observations.firstOrNull()?.year ?: return
    val lastYear = observations.last().year
    if (firstYear >= lastYear) return
    val pointColor = MaterialTheme.colorScheme.primary
    val gridColor = MaterialTheme.colorScheme.outlineVariant
    val labelStyle = MaterialTheme.typography.labelSmall.copy(color = MaterialTheme.colorScheme.onSurfaceVariant)
    val measurer = rememberTextMeasurer()
    val middle = firstYear + (lastYear - firstYear) / 2
    val axisYears = if (firstYear < middle) listOf(firstYear, middle, lastYear) else listOf(firstYear, lastYear)
    val description = "$metric: " + observations.joinToString { "${it.year}, ${String.format(Locale.getDefault(), "%.${decimals}f", it.value)}" }

    Canvas(
        modifier = Modifier
            .fillMaxWidth()
            .height(150.dp)
            .padding(top = 4.dp)
            .clearAndSetSemantics { contentDescription = description },
    ) {
        val padding = 20.dp.toPx()
        val labelHeight = 16.dp.toPx()
        val plotBottom = size.height - labelHeight
        fun x(year: Int) = padding + (year - firstYear).toFloat() / (lastYear - firstYear) * (size.width - padding * 2)
        fun y(value: Double) = plotBottom - (value / upperBound).toFloat().coerceIn(0f, 1f) * plotBottom

        axisYears.forEach { year ->
            drawLine(gridColor, Offset(x(year), 0f), Offset(x(year), plotBottom), strokeWidth = 1.dp.toPx())
            drawYearLabel(measurer, year, x(year), plotBottom, labelStyle)
        }
        drawLine(gridColor, Offset(0f, plotBottom), Offset(size.width, plotBottom), strokeWidth = 1.dp.toPx())
        observations.forEach { observation ->
            drawCircle(pointColor, radius = 4.dp.toPx(), center = Offset(x(observation.year), y(observation.value)))
        }
    }
}

private fun DrawScope.drawYearLabel(
    measurer: TextMeasurer,
    year: Int,
    centerX: Float,
    top: Float,
    style: TextStyle,
) {
    val layout = measurer.measure(year.toString(), style)
    val left = (centerX - layout.size.width / 2f).coerceIn(0f, size.width - layout.size.width)
    drawText(layout, topLeft = Offset(left, top + 2.dp.toPx()))
}

@Preview
@Composable
private fun DemocracySafetyPreview() {
    TellusTheme {
        Column {
            DemocracySection(
                LoadState.Loaded(
                    DemocracyProfile(
                        16,
                        listOf(
                            DemocracyProfile.Series(
                                "SWE",
                                null,
                                listOf(AnnualObservation(2023, 0.73), AnnualObservation(2024, 0.78), AnnualObservation(2025, 0.80)),
                            ),
                        ),
                    ),
                ),
            )
            HomicideSection(LoadState.Failed) {}
        }
    }
}

@Preview
@Composable
private fun DemocracySafetyEmptyPreview() {
    TellusTheme {
        Column {
            DemocracySection(LoadState.Loaded(DemocracyProfile(16, emptyList())))
            HomicideSection(LoadState.Loaded(emptyList())) {}
        }
    }
}
