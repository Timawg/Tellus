package com.pathos.tellus.hazards

import android.content.Context
import android.graphics.BlurMaskFilter
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.Color as AndroidColor
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.core.graphics.createBitmap
import com.google.android.gms.maps.model.BitmapDescriptor
import com.google.android.gms.maps.model.BitmapDescriptorFactory
import com.google.android.gms.maps.model.Dash
import com.google.android.gms.maps.model.Gap
import com.google.android.gms.maps.model.LatLng
import com.google.android.gms.maps.model.RoundCap
import com.google.maps.android.compose.Marker
import com.google.maps.android.compose.Polyline
import com.google.maps.android.compose.rememberUpdatedMarkerState
import com.pathos.tellus.ui.theme.AlertOrange
import com.pathos.tellus.ui.theme.AlertRed
import kotlin.math.max
import kotlin.math.min

/** The colour of a hazard's badge and track: yellow, orange or red by severity, as on iOS. */
val NaturalHazard.Severity.color: Color
    get() = when (this) {
        NaturalHazard.Severity.MINOR -> Color(0xFFFFCC00)
        NaturalHazard.Severity.MODERATE -> AlertOrange
        NaturalHazard.Severity.SEVERE -> AlertRed
    }

/**
 * Hazard badges and cyclone tracks, drawn inside the GoogleMap content.
 * Ported from iOS `HazardMapLayer`. MapKit hides lesser badges where they'd
 * overlap; Google Maps has no collision hiding, so every badge is drawn and
 * severe ones sit on top.
 */
@Composable
fun HazardsLayer(hazards: List<NaturalHazard>, tracks: List<CycloneTrack>, onSelect: (String) -> Unit) {
    val context = LocalContext.current
    val density = LocalDensity.current.density
    val badges = remember(density) { mutableMapOf<String, BitmapDescriptor>() }
    val strokeWidth = with(LocalDensity.current) { 3.dp.toPx() }

    tracks.forEach { track ->
        val color = track.severity.color
        track.observed.forEach { segment ->
            Polyline(segment.map { LatLng(it.latitude, it.longitude) }, color = color.copy(alpha = 0.9f), width = strokeWidth, startCap = RoundCap(), endCap = RoundCap(), zIndex = 1f)
        }
        val dashes = listOf(Dash(4 * density), Gap(6 * density))
        track.forecast.forEach { segment ->
            Polyline(segment.map { LatLng(it.latitude, it.longitude) }, color = color.copy(alpha = 0.7f), width = strokeWidth, pattern = dashes, zIndex = 1f)
        }
    }

    hazards.forEach { hazard ->
        val diameter = diameter(hazard)
        val key = "${hazard.kind}-${hazard.severity}-$diameter"
        Marker(
            state = rememberUpdatedMarkerState(LatLng(hazard.coordinate.latitude, hazard.coordinate.longitude)),
            icon = badges.getOrPut(key) { badge(context, hazard, diameter, density) },
            anchor = Offset(0.5f, 0.5f),
            // Above cable landing points and below aircraft, as on iOS.
            zIndex = 0.2f + hazard.severity.ordinal * 0.05f,
            contentDescription = "${hazard.kind.title}: ${hazard.name}",
            onClick = {
                onSelect(hazard.id)
                true
            },
        )
    }
}

/** Earthquakes grow with magnitude: M4.5 → 18 dp, M7 and up → 32 dp. Everything else is 26 dp. */
private fun diameter(hazard: NaturalHazard): Int {
    val magnitude = hazard.magnitude ?: return 26
    return (18 + min(max(magnitude - 4.5, 0.0), 2.5) / 2.5 * 14).toInt()
}

/** A coloured circle with a white ring and the hazard's symbol, drawn once per kind, severity and size. */
private fun badge(context: Context, hazard: NaturalHazard, diameterDp: Int, density: Float): BitmapDescriptor {
    val diameter = diameterDp * density
    val inset = 4 * density
    val size = (diameter + inset * 2).toInt()
    val bitmap = createBitmap(size, size)
    val center = size / 2f
    Canvas(bitmap).apply {
        val shadow = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = AndroidColor.argb(128, 0, 0, 0)
            maskFilter = BlurMaskFilter(3 * density / 2, BlurMaskFilter.Blur.NORMAL)
        }
        drawCircle(center, center + density, diameter / 2, shadow)
        drawCircle(center, center, diameter / 2, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = hazard.severity.color.toArgb() })
        val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = 1.5f * density
            color = AndroidColor.argb(230, 255, 255, 255)
        }
        drawCircle(center, center, diameter / 2 - 0.75f * density, ring)
        val icon = hazard.kind.iconRes?.let { ContextCompat.getDrawable(context, it) }
        if (icon != null) {
            // White, at 60% of the badge, like iOS's symbol inside its circle.
            val half = (diameter * 0.3f).toInt()
            icon.setBounds(center.toInt() - half, center.toInt() - half, center.toInt() + half, center.toInt() + half)
            icon.draw(this)
        } else {
            val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                textSize = diameter * 0.5f
                textAlign = Paint.Align.CENTER
            }
            val bounds = Rect().also { text.getTextBounds(hazard.kind.symbol, 0, hazard.kind.symbol.length, it) }
            drawText(hazard.kind.symbol, center, center - bounds.exactCenterY(), text)
        }
    }
    return BitmapDescriptorFactory.fromBitmap(bitmap)
}
