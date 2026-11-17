package com.pathos.tellus.flights

import android.text.format.DateUtils
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import com.pathos.tellus.R
import com.pathos.tellus.guide.GuideSection
import com.pathos.tellus.guide.LabeledRow
import com.pathos.tellus.guide.LoadingRow
import com.pathos.tellus.guide.SecondaryText
import com.pathos.tellus.guide.SourceLink
import com.pathos.tellus.guide.weather.rememberMinuteTicker
import java.text.NumberFormat
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * Details for the selected aircraft: its route and photo from adsbdb.com, live
 * values from OpenSky or, for military aircraft, adsb.lol (updated on every
 * poll) and its registration. Ported from iOS `FlightDetailsView`.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FlightDetailsSheet(flightId: String, state: LiveFlightsUiState, onDismiss: () -> Unit) {
    val flight = state.flights[flightId]
    val aircraft = state.selectedAircraft
    // Kept once known, so the footer doesn't change if the aircraft drops out of the feed while the sheet is open.
    var wasMilitary by remember(flightId) { mutableStateOf(false) }
    flight?.let { wasMilitary = it.isMilitary }
    val isMilitary = flight?.isMilitary ?: wasMilitary
    val title = flight?.callsign ?: flight?.registration ?: aircraft?.registration ?: flightId.uppercase()

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState()) {
        Column(Modifier.fillMaxSize()) {
            Row(Modifier.fillMaxWidth().padding(start = 24.dp, end = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(title, Modifier.weight(1f), style = MaterialTheme.typography.titleLarge)
                TextButton(onClick = onDismiss) { Text("Done") }
            }
            LazyColumn(contentPadding = PaddingValues(bottom = 32.dp)) {
                item { RouteSection(state, flight) }
                aircraft?.urlPhoto?.let { photo -> item { PhotoSection(photo) } }
                item { LiveSection(flight) }
                item { AircraftSection(flightId, flight, aircraft, state.isLoadingDetails) }
                item {
                    GuideSection(header = null) {
                        if (isMilitary) SourceLink("Track on adsb.lol", "https://globe.adsb.lol/?icao=$flightId")
                        SecondaryText(
                            if (isMilitary) {
                                "Military aircraft. Live position from adsb.lol, a community network of ADS-B receivers (ODbL); " +
                                    "only aircraft that broadcast a position are shown. Aircraft and route from adsbdb.com, " +
                                    "which is community-maintained and may be incomplete."
                            } else {
                                "Live position from The OpenSky Network. Aircraft and route from adsbdb.com, " +
                                    "which is community-maintained and may be incomplete."
                            },
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun RouteSection(state: LiveFlightsUiState, flight: LiveFlight?) {
    GuideSection("Route") {
        val route = state.selectedRoute
        when {
            route != null -> {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Airport(route.origin, Alignment.Start, Modifier.weight(1f))
                    // The map marker, turned to fly from origin to destination.
                    Image(
                        painterResource(R.drawable.aircraft),
                        contentDescription = null,
                        modifier = Modifier.size(32.dp).rotate(90f),
                    )
                    Airport(route.destination, Alignment.End, Modifier.weight(1f))
                }
                flight?.let { current ->
                    val (flown, remaining, fraction) = route.progress(current.coordinate)
                    LinearProgressIndicator(progress = { fraction.toFloat() }, modifier = Modifier.fillMaxWidth())
                    Row(Modifier.fillMaxWidth()) {
                        val small = MaterialTheme.typography.bodySmall
                        val color = MaterialTheme.colorScheme.onSurfaceVariant
                        Text("${kilometres(flown)} flown", Modifier.weight(1f), style = small, color = color)
                        Text("${kilometres(remaining)} to go", style = small, color = color)
                    }
                }
                route.airline?.name?.let { LabeledRow("Airline", it) }
                route.callsignIata?.takeIf { it != route.callsign }?.let { LabeledRow("Flight number", it) }
            }
            state.isLoadingDetails -> LoadingRow("Looking up…")
            else -> SecondaryText("Route not available")
        }
    }
}

@Composable
private fun Airport(airport: FlightRoute.Airport, alignment: Alignment.Horizontal, modifier: Modifier) {
    val place = airport.municipality ?: airport.name
    Column(
        modifier.clearAndSetSemantics { contentDescription = "${airport.code}, $place" },
        horizontalAlignment = alignment,
    ) {
        Text(airport.code, style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
        Text(
            place,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            textAlign = if (alignment == Alignment.End) TextAlign.End else TextAlign.Start,
        )
    }
}

@Composable
private fun PhotoSection(url: String) {
    GuideSection(header = null, footer = { Text("Photo: airport-data.com") }) {
        AsyncImage(
            model = url,
            contentDescription = "Photo of the aircraft",
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxWidth().height(190.dp).clip(RoundedCornerShape(8.dp)),
        )
    }
}

@Composable
private fun LiveSection(flight: LiveFlight?) {
    GuideSection("Live") {
        if (flight == null) {
            SecondaryText("No live data for this flight right now.")
            return@GuideSection
        }
        if (flight.isMilitary) Text("🛡️ Military aircraft", color = MilitaryAircraftGreen)
        flight.emergency?.let { Text("⚠️ Emergency: $it", color = MaterialTheme.colorScheme.error) }
        if (!flight.isOnGround) flight.altitudeMeters?.let { LabeledRow("Altitude", altitudeText(it)) }
        flight.speedMetersPerSecond?.let { LabeledRow("Speed", speedText(it)) }
        flight.track?.let { LabeledRow("Heading", headingText(it)) }
        if (flight.isOnGround) {
            LabeledRow("Status", "On the ground")
        } else {
            flight.verticalRateMetersPerSecond?.let { LabeledRow("Vertical speed", verticalRateText(it)) }
        }
        flight.squawk?.let { squawk ->
            // Codes pilots set to signal trouble.
            val meaning = mapOf("7500" to "Hijack", "7600" to "Radio failure", "7700" to "Emergency")[squawk]
            Row(Modifier.fillMaxWidth().semantics(mergeDescendants = true) {}) {
                Text("Squawk", Modifier.weight(1f))
                Text(
                    meaning?.let { "$squawk · $it" } ?: squawk,
                    color = if (meaning == null) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.error,
                )
            }
        }
        val now = rememberMinuteTicker()
        LabeledRow(
            "Last update",
            DateUtils.getRelativeTimeSpanString(flight.lastContact.toEpochMilli(), now.toEpochMilli(), DateUtils.SECOND_IN_MILLIS).toString(),
        )
    }
}

@Composable
private fun AircraftSection(flightId: String, flight: LiveFlight?, aircraft: AircraftInfo?, isLoading: Boolean) {
    GuideSection("Aircraft") {
        val type = aircraft?.displayType
        if (type != null) LabeledRow("Type", type) else flight?.typeCode?.let { LabeledRow("Type code", it) }
        (aircraft?.registration ?: flight?.registration)?.let { LabeledRow("Registration", it) }
        aircraft?.registeredOwner?.let { LabeledRow("Operator", it) }
        (aircraft?.registeredOwnerCountryName ?: flight?.originCountry)?.let { LabeledRow("Registered in", it) }
        LabeledRow("ICAO address", flightId.uppercase())
        if (aircraft == null && isLoading) LoadingRow("Looking up…")
    }
}

private fun number(value: Double): String = NumberFormat.getIntegerInstance().format(value.roundToInt())

internal fun altitudeText(meters: Double) = "${number(meters / 0.3048)} ft · ${number(meters)} m"

internal fun speedText(metersPerSecond: Double) = "${number(metersPerSecond * 3.6)} km/h · ${number(metersPerSecond / 0.514444)} kn"

/** "178° S". */
internal fun headingText(degrees: Double): String {
    val points = listOf("N", "NE", "E", "SE", "S", "SW", "W", "NW")
    val index = (((degrees % 360) + 22.5) / 45).toInt() % points.size
    return "${degrees.roundToInt()}° ${points[index]}"
}

internal fun verticalRateText(metersPerSecond: Double): String {
    val feetPerMinute = metersPerSecond * 196.85
    if (abs(feetPerMinute) < 100) return "Level"
    val rate = number(abs(feetPerMinute))
    return if (feetPerMinute > 0) "Climbing $rate ft/min" else "Descending $rate ft/min"
}

private fun kilometres(meters: Double) = "${number(meters / 1000)} km"
