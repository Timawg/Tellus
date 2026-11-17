package com.pathos.tellus.hazards

import android.text.format.DateUtils
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.pathos.tellus.guide.GuideSection
import com.pathos.tellus.guide.LabeledRow
import com.pathos.tellus.guide.SecondaryText
import com.pathos.tellus.guide.SourceLink
import com.pathos.tellus.guide.weather.rememberMinuteTicker
import com.pathos.tellus.map.Coordinate
import com.pathos.tellus.ui.theme.AlertOrange
import com.pathos.tellus.ui.theme.AlertRed
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import kotlin.math.abs

/**
 * A natural hazard tapped on the map: what it is, how strong, when it began
 * and a link to the source's own report. Ported from iOS `HazardDetailsView`.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HazardDetailsSheet(hazard: NaturalHazard, onDismiss: () -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState()) {
        Row(Modifier.fillMaxWidth().padding(start = 24.dp, end = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(hazard.kind.title, Modifier.weight(1f), style = MaterialTheme.typography.titleLarge)
            TextButton(onClick = onDismiss) { Text("Done") }
        }
        LazyColumn(contentPadding = PaddingValues(bottom = 32.dp)) {
            item {
                GuideSection(header = null) {
                    Header(hazard)
                    DetailRows(hazard)
                }
            }
            item {
                GuideSection(header = null) {
                    hazard.url?.let { SourceLink(linkTitle(hazard.source), it) }
                    SecondaryText(attribution(hazard.source))
                }
            }
        }
    }
}

@Composable
private fun Header(hazard: NaturalHazard) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(
            Modifier.size(40.dp).background(hazard.severity.color, CircleShape).clearAndSetSemantics { },
            contentAlignment = Alignment.Center,
        ) { HazardSymbol(hazard.kind, tint = Color.White) }
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(hazard.name, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            hazard.place?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        }
    }
}

@Composable
private fun DetailRows(hazard: NaturalHazard) {
    val zone = ZoneId.systemDefault()
    val dateTime = DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT).withZone(zone)
    val date = DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withZone(zone)
    when (hazard.kind) {
        DisasterAlert.Kind.EARTHQUAKE -> {
            hazard.magnitude?.let { LabeledRow("Magnitude", String.format(Locale.getDefault(), "%.1f", it)) }
            hazard.depth?.let { LabeledRow("Depth", String.format(Locale.getDefault(), "%.0f km", it)) }
            hazard.date?.let {
                val now = rememberMinuteTicker()
                LabeledRow("Struck", DateUtils.getRelativeTimeSpanString(it.toEpochMilli(), now.toEpochMilli(), DateUtils.MINUTE_IN_MILLIS).toString())
                LabeledRow("Date", dateTime.format(it))
            }
            hazard.alertLevel?.let { LevelRow("Estimated impact", it) }
            if (hazard.mayCauseTsunami) {
                Text(
                    "🌊 In an ocean region where a tsunami is possible. Follow local warnings.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = AlertOrange,
                )
            }
        }
        DisasterAlert.Kind.VOLCANO -> {
            hazard.date?.let { LabeledRow("Erupting since", eruptionStart(it, Instant.now(), zone)) }
            hazard.explosivity?.let { LabeledRow("Largest explosion", "VEI $it of 8") }
            hazard.alertLevel?.let { LevelRow("GDACS alert", it) }
        }
        else -> {
            hazard.alertLevel?.let { LevelRow("GDACS alert", it) }
            hazard.summary?.let { LabeledRow(summaryLabel(hazard.kind), it) }
            hazard.date?.let { LabeledRow("Began", date.format(it)) }
            hazard.updated?.let { LabeledRow("Last report", dateTime.format(it)) }
        }
    }
    LabeledRow("Location", coordinateText(hazard.coordinate))
}

@Composable
private fun LevelRow(label: String, level: String) {
    Row(Modifier.fillMaxWidth()) {
        Text(label, Modifier.weight(1f))
        Text(impactText(level), color = levelColor(level) ?: MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

private fun summaryLabel(kind: DisasterAlert.Kind) = when (kind) {
    DisasterAlert.Kind.CYCLONE -> "Wind"
    DisasterAlert.Kind.WILDFIRE -> "Area"
    else -> "Severity"
}

private fun linkTitle(source: NaturalHazard.Source) = when (source) {
    NaturalHazard.Source.USGS -> "View on USGS"
    NaturalHazard.Source.GDACS -> "View GDACS report"
    NaturalHazard.Source.SMITHSONIAN -> "View on the Global Volcanism Program"
}

private fun attribution(source: NaturalHazard.Source) = when (source) {
    NaturalHazard.Source.USGS -> "Earthquake data from the U.S. Geological Survey. Magnitude 4.5 and up from the past week."
    NaturalHazard.Source.GDACS ->
        "From GDACS, the Global Disaster Alert and Coordination System of the United Nations and the European Commission. " +
            "Alerts estimate humanitarian impact."
    NaturalHazard.Source.SMITHSONIAN ->
        "Ongoing eruptions from the Smithsonian Institution's Global Volcanism Program. " +
            "Activity varies; check local authorities before visiting."
}

internal fun impactText(level: String) = when (level.lowercase()) {
    "green" -> "Green · low"
    "yellow" -> "Yellow · moderate"
    "orange" -> "Orange · significant"
    "red" -> "Red · severe"
    else -> level
}

private fun levelColor(level: String): Color? = when (level.lowercase()) {
    "green" -> Color(0xFF34C759)
    "yellow" -> Color(0xFFFFCC00)
    "orange" -> AlertOrange
    "red" -> AlertRed
    else -> null
}

/** Eruptions can have been going for decades; show the year for those. */
internal fun eruptionStart(date: Instant, now: Instant, zone: ZoneId): String =
    if (date.isBefore(now.minus(Duration.ofDays(365)))) {
        date.atZone(zone).year.toString()
    } else {
        DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withZone(zone).format(date)
    }

internal fun coordinateText(coordinate: Coordinate, locale: Locale = Locale.getDefault()): String {
    val latitude = String.format(locale, "%.2f", abs(coordinate.latitude))
    val longitude = String.format(locale, "%.2f", abs(coordinate.longitude))
    return "$latitude° ${if (coordinate.latitude >= 0) "N" else "S"}, $longitude° ${if (coordinate.longitude >= 0) "E" else "W"}"
}
