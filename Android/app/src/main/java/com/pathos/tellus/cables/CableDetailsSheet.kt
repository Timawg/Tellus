package com.pathos.tellus.cables

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.pathos.tellus.guide.GuideSection
import com.pathos.tellus.guide.LabeledRow
import com.pathos.tellus.guide.LoadingRow
import com.pathos.tellus.guide.RetryButton
import com.pathos.tellus.guide.SecondaryText
import com.pathos.tellus.guide.SourceLink

/**
 * An undersea cable tapped on the map: its length, owners, when it entered
 * service and where it comes ashore. Ported from iOS `CableDetailsView`.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CableDetailsSheet(cable: SubmarineCable, details: CableDetails?, detailsFailed: Boolean, onRetry: () -> Unit, onDismiss: () -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState()) {
        Row(Modifier.fillMaxWidth().padding(start = 24.dp, end = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("Undersea cable", Modifier.weight(1f), style = MaterialTheme.typography.titleLarge)
            TextButton(onClick = onDismiss) { Text("Done") }
        }
        LazyColumn(contentPadding = PaddingValues(bottom = 32.dp)) {
            item {
                GuideSection(header = null) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Box(
                            Modifier
                                .size(width = 28.dp, height = 6.dp)
                                .background(cable.color, RoundedCornerShape(3.dp))
                                .clearAndSetSemantics { },
                        )
                        Text(cable.name, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    }
                    when {
                        details != null -> Facts(details)
                        detailsFailed -> {
                            SecondaryText("Couldn’t load this cable’s details.")
                            RetryButton(onRetry)
                        }
                        else -> LoadingRow("Loading details…")
                    }
                }
            }
            val groups = details?.landingPointsByCountry.orEmpty()
            if (groups.isNotEmpty()) {
                item {
                    GuideSection(header = "Comes ashore in") {
                        groups.forEach { (country, points) -> CountryGroup(country, points) }
                    }
                }
            }
            item {
                GuideSection(header = null) {
                    details?.let { SourceLink("View on Submarine Cable Map", it.mapUrl) }
                    details?.url?.takeIf { it.isNotBlank() }?.let { SourceLink("Cable website", it) }
                    SecondaryText("Cable data © TeleGeography, submarinecablemap.com.")
                }
            }
        }
    }
}

@Composable
private fun Facts(details: CableDetails) {
    details.length?.let { LabeledRow("Length", it) }
    details.rfsYear?.let { LabeledRow(if (details.isPlanned == true) "Planned for" else "In service since", it.toString()) }
    if (details.landingPoints.isNotEmpty()) {
        val countries = details.landingPointsByCountry.size
        LabeledRow("Landing points", "${details.landingPoints.size} in $countries ${if (countries == 1) "country" else "countries"}")
    }
    details.owners?.takeIf { it.isNotEmpty() }?.let { LabeledRow("Owners", it) }
    details.suppliers?.takeIf { it.isNotEmpty() }?.let { LabeledRow("Built by", it) }
}

/** A country and its landing point count, expanding to list them, like iOS's `DisclosureGroup`. */
@Composable
private fun CountryGroup(country: String, points: List<CableDetails.LandingPoint>) {
    var expanded by rememberSaveable(country) { mutableStateOf(false) }
    Column {
        Row(
            Modifier
                .fillMaxWidth()
                .clickable(role = Role.Button) { expanded = !expanded }
                .semantics { stateDescription = if (expanded) "Expanded" else "Collapsed" },
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(if (expanded) "▾" else "▸", Modifier.padding(end = 8.dp).clearAndSetSemantics { }, color = MaterialTheme.colorScheme.onSurfaceVariant)
            LabeledRow(country, points.size.toString(), Modifier.weight(1f))
        }
        if (expanded) {
            points.forEach { point ->
                Text(point.name, Modifier.padding(start = 24.dp, top = 6.dp), style = MaterialTheme.typography.bodyMedium)
            }
        }
    }
}
