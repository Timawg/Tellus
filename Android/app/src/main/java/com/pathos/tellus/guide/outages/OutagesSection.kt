package com.pathos.tellus.guide.outages

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.pathos.tellus.guide.GuideSection
import com.pathos.tellus.ui.theme.DisruptionPurple
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

/** Corroborated internet outages over the last week, as in the iOS guide's Connectivity section. */
@Composable
fun OutagesSection(outages: List<InternetOutage>) {
    val zone = ZoneId.systemDefault()
    val dateTime = DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT).withZone(zone)
    val time = DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withZone(zone)
    GuideSection(
        header = "Connectivity",
        footer = {
            Text(
                "Outages in the last 7 days seen by at least two independent signals, from IODA (Georgia Tech). " +
                    "A drop can mean a shutdown, a power cut or a cable fault.",
            )
        },
    ) {
        outages.forEach { outage ->
            val title = if (outage.isOngoing) "Internet disruption detected" else "Recent internet disruption"
            val period = if (outage.isOngoing) {
                "Since ${dateTime.format(outage.start)}"
            } else {
                "${dateTime.format(outage.start)} – ${time.format(outage.end)}"
            }
            val signals = "Seen in: ${outage.signals.joinToString(", ")}"
            Column(
                modifier = Modifier.clearAndSetSemantics { contentDescription = "$title. $period. $signals" },
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Text(
                    "📶 $title",
                    fontWeight = FontWeight.SemiBold,
                    color = if (outage.isOngoing) DisruptionPurple else MaterialTheme.colorScheme.onSurface,
                )
                Text(period, style = MaterialTheme.typography.bodyMedium)
                Text(signals, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}
