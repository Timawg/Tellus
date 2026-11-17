package com.pathos.tellus.guide.outbreaks

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.pathos.tellus.guide.GuideSection
import com.pathos.tellus.guide.SourceLink
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

/** WHO Disease Outbreak News reports naming the country, the latest per disease. */
@Composable
fun OutbreaksSection(reports: List<OutbreakReport>) {
    val date = DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withZone(ZoneId.systemDefault())
    GuideSection(
        header = "Outbreak news",
        footer = { Text("WHO Disease Outbreak News reports naming this country, the latest per disease.") },
    ) {
        reports.take(5).forEach { report ->
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    date.format(report.published),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(report.disease, fontWeight = FontWeight.SemiBold)
                if (report.summary.isNotEmpty()) Text(report.summary, style = MaterialTheme.typography.bodyMedium)
                report.url?.let { SourceLink("Read the WHO report", it) }
            }
        }
    }
}
