package com.pathos.tellus.hazards

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.pathos.tellus.guide.GuideSection
import com.pathos.tellus.guide.SourceLink
import com.pathos.tellus.ui.theme.AlertOrange
import com.pathos.tellus.ui.theme.AlertRed
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

/** The colour iOS gives an alert level. */
val DisasterAlert.Level.color: Color
    get() = if (this == DisasterAlert.Level.RED) AlertRed else AlertOrange

/** Active GDACS alerts for the country, as in the iOS guide's Climate tab. */
@Composable
fun DisasterAlertsSection(alerts: List<DisasterAlert>) {
    val date = DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withZone(ZoneId.systemDefault())
    GuideSection(
        header = "Active alerts",
        footer = { Text("Disaster alerts from GDACS, the Global Disaster Alert and Coordination System.") },
    ) {
        alerts.forEach { alert ->
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    HazardSymbol(alert.kind, tint = alert.level.color)
                    Text(alert.name, fontWeight = FontWeight.SemiBold)
                }
                alert.severity?.let { Text(it, style = MaterialTheme.typography.bodyMedium) }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    val small = MaterialTheme.typography.bodySmall
                    Text("${alert.level.title} alert", style = small, color = alert.level.color)
                    alert.start?.let {
                        Text("since ${date.format(it)}", style = small, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Text("", Modifier.weight(1f))
                    alert.reportUrl?.let { SourceLink("Report", it) }
                }
            }
        }
    }
}
