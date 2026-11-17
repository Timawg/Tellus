package com.pathos.tellus.guide.events

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.dp
import com.pathos.tellus.guide.GuideSection
import com.pathos.tellus.guide.SourceLink
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

/** The latest events, newest first, with older ones behind "More events", as in iOS `RecentEventsSection`. */
@Composable
fun RecentEventsSection(recentEvents: RecentEvents) {
    val shown = 5
    val events = recentEvents.events
    var showsMore by rememberSaveable(recentEvents.articleTitle) { mutableStateOf(false) }
    GuideSection(
        header = "Recent events",
        footer = {
            Text("From the Wikipedia article “${recentEvents.articleTitle}”, written by volunteers (CC BY-SA 4.0).")
            SourceLink("Read on Wikipedia", recentEvents.articleUrl)
        },
    ) {
        events.take(shown).forEach { EventRow(it) }
        if (events.size > shown) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(role = Role.Button) { showsMore = !showsMore }
                    .semantics { stateDescription = if (showsMore) "Expanded" else "Collapsed" },
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("More events", Modifier.weight(1f), color = MaterialTheme.colorScheme.primary)
                Icon(
                    if (showsMore) Icons.Filled.KeyboardArrowUp else Icons.Filled.KeyboardArrowDown,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                )
            }
            if (showsMore) events.drop(shown).take(25).forEach { EventRow(it) }
        }
    }
}

private val eventDate: DateTimeFormatter = DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM)

@Composable
private fun EventRow(event: RecentEvent) {
    val date = eventDate.format(event.date)
    Column(
        modifier = Modifier.clearAndSetSemantics { contentDescription = "$date. ${event.text}" },
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(
            date,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(event.text, style = MaterialTheme.typography.bodyMedium)
    }
}
