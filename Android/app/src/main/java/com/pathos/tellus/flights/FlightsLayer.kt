package com.pathos.tellus.flights

import android.content.Context
import android.graphics.BitmapFactory
import android.graphics.BlurMaskFilter
import android.graphics.Canvas
import android.graphics.Color as AndroidColor
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffColorFilter
import android.provider.Settings
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.key
import androidx.compose.runtime.remember
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import androidx.core.graphics.createBitmap
import androidx.core.graphics.scale
import com.google.android.gms.maps.model.BitmapDescriptor
import com.google.android.gms.maps.model.BitmapDescriptorFactory
import com.google.android.gms.maps.model.JointType
import com.google.android.gms.maps.model.LatLng
import com.google.android.gms.maps.model.RoundCap
import com.google.maps.android.compose.Marker
import com.google.maps.android.compose.MarkerState
import com.google.maps.android.compose.Polyline
import com.pathos.tellus.R
import com.pathos.tellus.map.Coordinate
import kotlin.math.ceil

/** Military aircraft are drawn in this green, so they stand apart from civil flights, as on iOS. */
val MilitaryAircraftGreen = Color(0xFF99CC59)

/**
 * The aircraft markers and the selected flight's route, drawn inside the
 * GoogleMap content. Ported from iOS `FlightMapLayer` and
 * `FlightRouteMapLayer`.
 *
 * When a poll moves aircraft, one 1 s animation moves them all from where
 * they're drawn to their new positions by updating each marker's state
 * directly, rather than starting an animation per marker.
 */
@Composable
fun FlightsLayer(
    markers: List<FlightMarker>,
    selectedId: String?,
    route: FlightRoute?,
    flights: Map<String, LiveFlight>,
    onSelect: (String) -> Unit,
) {
    val icons = rememberAircraftIcons()
    val states = remember { mutableMapOf<String, MarkerState>() }

    LaunchedEffect(markers) {
        val wanted = markers.associateBy { it.id }
        states.keys.retainAll(wanted.keys)
        val moves = markers.mapNotNull { marker ->
            val state = states[marker.id] ?: return@mapNotNull null
            val from = state.position
            val to = LatLng(marker.latitude, marker.longitude)
            if (from == to) return@mapNotNull null
            // The route and its aircraft must move to the new position together.
            if (marker.id == selectedId && route != null) {
                state.position = to
                null
            } else {
                Triple(state, from, to)
            }
        }
        if (moves.isEmpty()) return@LaunchedEffect
        val start = withFrameNanos { it }
        while (true) {
            val elapsed = withFrameNanos { it } - start
            val fraction = (elapsed / MOVE_DURATION_NANOS.toDouble()).coerceAtMost(1.0)
            for ((state, from, to) in moves) {
                state.position = LatLng(
                    from.latitude + (to.latitude - from.latitude) * fraction,
                    from.longitude + (to.longitude - from.longitude) * fraction,
                )
            }
            if (fraction >= 1.0) break
        }
    }

    markers.forEach { marker ->
        key(marker.id) {
            val state = states.getOrPut(marker.id) { MarkerState(LatLng(marker.latitude, marker.longitude)) }
            val isSelected = marker.id == selectedId
            val isMilitary = marker.source == LiveFlight.Source.ADSB_LOL_MILITARY
            val callsign = flights[marker.id]?.callsign
            Marker(
                state = state,
                icon = icons.of(isMilitary, isSelected),
                rotation = marker.track ?: 0f,
                flat = true,
                anchor = Offset(0.5f, 0.5f),
                zIndex = if (isSelected) 2f else 1f,
                contentDescription = listOfNotNull(if (isMilitary) "Military aircraft" else "Aircraft", callsign).joinToString(", "),
                onClick = {
                    onSelect(marker.id)
                    true
                },
            )
        }
    }

    val aircraft = selectedId?.let { id -> markers.firstOrNull { it.id == id }?.coordinate }
    if (route != null && aircraft != null) RouteLine(route, aircraft)
}

/** The route from origin through the aircraft to destination, drawn as great circles that sweep in once. */
@Composable
private fun RouteLine(route: FlightRoute, aircraft: Coordinate) {
    val coordinates = route.mapCoordinates(aircraft) ?: return
    val points = remember(coordinates) {
        (Geo.greatCircle(coordinates[0], coordinates[1], SEGMENTS) + Geo.greatCircle(coordinates[1], coordinates[2], SEGMENTS).drop(1))
            .map { LatLng(it.latitude, it.longitude) }
    }
    val context = LocalContext.current
    val progress = remember(route) { Animatable(if (reducesMotion(context)) 1f else 0f) }
    LaunchedEffect(route) { progress.animateTo(1f, tween(800, easing = LinearEasing)) }
    val shown = points.take(maxOf(2, ceil(progress.value * points.size).toInt()))
    Polyline(
        points = shown,
        color = Color(0xFF32ADE6),
        width = with(LocalDensity.current) { 3.dp.toPx() },
        jointType = JointType.ROUND,
        startCap = RoundCap(),
        endCap = RoundCap(),
        zIndex = 3f,
    )
}

/** Animations off in developer options or accessibility settings stand in for iOS's Reduce Motion. */
private fun reducesMotion(context: Context): Boolean =
    Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f

private class AircraftIcons(
    val civil: BitmapDescriptor,
    val military: BitmapDescriptor,
    val civilSelected: BitmapDescriptor,
    val militarySelected: BitmapDescriptor,
) {
    fun of(military: Boolean, selected: Boolean) = when {
        military && selected -> militarySelected
        military -> this.military
        selected -> civilSelected
        else -> civil
    }
}

/**
 * The aircraft with its drop shadow drawn in, made once and shared by every
 * marker, as iOS does: 20 × 25 dp, and 1.5× when selected.
 */
@Composable
private fun rememberAircraftIcons(): AircraftIcons {
    val context = LocalContext.current
    val density = LocalDensity.current.density
    return remember(density) {
        val source = BitmapFactory.decodeResource(context.resources, R.drawable.aircraft)
        fun icon(tint: Int?, scale: Float): BitmapDescriptor {
            val width = (20 * scale * density).toInt()
            val height = (25 * scale * density).toInt()
            val inset = (4 * density).toInt()
            val aircraft = source.scale(width, height)
            val canvas = createBitmap(width + inset * 2, height + inset * 2)
            Canvas(canvas).apply {
                val shadow = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    colorFilter = PorterDuffColorFilter(AndroidColor.argb(128, 0, 0, 0), PorterDuff.Mode.SRC_IN)
                    maskFilter = BlurMaskFilter(5 * density / 2, BlurMaskFilter.Blur.NORMAL)
                }
                drawBitmap(aircraft, inset.toFloat(), inset + density, shadow)
                drawBitmap(aircraft, inset.toFloat(), inset.toFloat(), null)
                if (tint != null) {
                    val overlay = createBitmap(width, height).also { Canvas(it).drawBitmap(aircraft, 0f, 0f, null) }
                    Canvas(overlay).drawColor(tint, PorterDuff.Mode.SRC_ATOP)
                    drawBitmap(overlay, inset.toFloat(), inset.toFloat(), null)
                }
            }
            return BitmapDescriptorFactory.fromBitmap(canvas)
        }
        val green = AndroidColor.argb(191, 153, 204, 89)
        AircraftIcons(icon(null, 1f), icon(green, 1f), icon(null, 1.5f), icon(green, 1.5f))
    }
}

private const val MOVE_DURATION_NANOS = 1_000_000_000L
private const val SEGMENTS = 64
