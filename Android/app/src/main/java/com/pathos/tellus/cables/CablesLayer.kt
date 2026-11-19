package com.pathos.tellus.cables

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import androidx.core.graphics.createBitmap
import com.google.android.gms.maps.model.BitmapDescriptor
import com.google.android.gms.maps.model.BitmapDescriptorFactory
import com.google.android.gms.maps.model.JointType
import com.google.android.gms.maps.model.LatLng
import com.google.android.gms.maps.model.RoundCap
import com.google.android.gms.maps.model.Tile
import com.google.android.gms.maps.model.TileProvider
import com.google.maps.android.compose.Marker
import com.google.maps.android.compose.Polyline
import com.google.maps.android.compose.TileOverlay
import com.google.maps.android.compose.rememberUpdatedMarkerState
import com.pathos.tellus.map.MercatorPoint
import com.pathos.tellus.map.MercatorRect
import java.io.ByteArrayOutputStream
import kotlin.math.min
import kotlin.math.pow

/** iOS draws a cable without a valid colour in `systemTeal`. */
private val FALLBACK_COLOR = Color(0xFF30B0C7)

/** A cable's colour, from TeleGeography's hex. */
val SubmarineCable.color: Color
    get() = parseHexColor(colorHex)?.let(::Color) ?: FALLBACK_COLOR

/**
 * Cable routes and landing points, drawn inside the GoogleMap content.
 * Ported from iOS `CableMapLayer` and `CableOverlay`.
 *
 * There are about 2,000 route segments and 2,000 landing points. As one
 * Polyline or Marker each they took seconds to add on the main thread and
 * the app stopped responding, so they're drawn into map tiles on the Maps
 * SDK's background threads instead. Only the selected cable is a Polyline,
 * so it can be highlighted, and only the tapped landing point is a Marker,
 * for its name. Taps are hit-tested by [CableLayerViewModel.tap], since a
 * 1.5 dp line is too thin to tap.
 */
@Composable
fun CablesLayer(dataset: CableDataset, selected: SubmarineCable?, selectedLandingPoint: CableLandingPoint?) {
    val density = LocalDensity.current.density
    val tiles = remember(dataset, density) { CableTileProvider(dataset.geometry, density) }
    // Below hazard tracks; the selected cable above the others.
    TileOverlay(tileProvider = tiles, zIndex = 0.5f, fadeIn = false)

    if (selected != null) {
        val width = with(LocalDensity.current) { 4.dp.toPx() }
        val lines = remember(selected) { selected.lines.map { line -> line.map { LatLng(it.latitude, it.longitude) } } }
        lines.forEach { line ->
            Polyline(
                points = line,
                color = selected.color,
                width = width,
                startCap = RoundCap(),
                endCap = RoundCap(),
                jointType = JointType.ROUND,
                zIndex = 0.6f,
            )
        }
    }

    if (selectedLandingPoint != null) {
        val dot = remember(density) { landingPointDot(density) }
        val state = rememberUpdatedMarkerState(LatLng(selectedLandingPoint.coordinate.latitude, selectedLandingPoint.coordinate.longitude))
        Marker(
            state = state,
            icon = dot,
            anchor = Offset(0.5f, 0.5f),
            title = selectedLandingPoint.name,
            // Below hazards and aircraft, as on iOS.
            zIndex = 0.1f,
        )
        LaunchedEffect(selectedLandingPoint) { state.showInfoWindow() }
    }
}

/**
 * Draws cables at 1.5 dp and 75% opacity, and landing point dots, as iOS's
 * renderer and annotation views do. The geometry is immutable, so tiles can
 * be drawn on several threads at once.
 */
private class CableTileProvider(private val geometry: CableGeometry, private val density: Float) : TileProvider {
    // A tile covers 256 dp on screen; drawing at screen pixels keeps it sharp.
    private val size = min((256 * density).toInt(), 768)
    private val pixelsPerDp = size / 256f
    private val dotRadius = 3 * pixelsPerDp

    override fun getTile(x: Int, y: Int, zoom: Int): Tile {
        val scale = 2.0.pow(zoom)
        val tile = MercatorRect(x / scale, y / scale, (x + 1) / scale, (y + 1) / scale)
        // How far past the tile a line or dot can still reach into it.
        val margin = 4.0 / (256 * scale)
        val reach = MercatorRect(tile.minX - margin, tile.minY - margin, tile.maxX + margin, tile.maxY + margin)
        val routes = geometry.routes.filter { it.bounds.distanceTo(reach) == 0.0 }
        val dots = visibleLandingPoints(geometry.points, reach, 8.0 / (256 * scale))
        if (routes.isEmpty() && dots.isEmpty()) return TileProvider.NO_TILE

        fun toPixels(point: MercatorPoint) = ((point.x - tile.minX) * scale * size).toFloat() to ((point.y - tile.minY) * scale * size).toFloat()

        val bitmap = createBitmap(size, size)
        val canvas = Canvas(bitmap)
        val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = 1.5f * pixelsPerDp
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        }
        for (route in routes) {
            stroke.color = route.cable.color.copy(alpha = 0.75f).toArgb()
            for (line in route.lines) {
                val path = Path()
                line.forEachIndexed { index, point ->
                    val (px, py) = toPixels(point)
                    if (index == 0) path.moveTo(px, py) else path.lineTo(px, py)
                }
                canvas.drawPath(path, stroke)
            }
        }
        val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = android.graphics.Color.argb(230, 255, 255, 255) }
        val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = pixelsPerDp
            color = android.graphics.Color.argb(128, 0, 0, 0)
        }
        for (dot in dots) {
            val (px, py) = toPixels(dot.position)
            canvas.drawCircle(px, py, dotRadius, fill)
            canvas.drawCircle(px, py, dotRadius, ring)
        }
        val png = ByteArrayOutputStream().use { stream ->
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
            stream.toByteArray()
        }
        bitmap.recycle()
        return Tile(size, size, png)
    }
}

/** A small white dot with a dark ring, like iOS's `LandingPointAnnotationView`. */
private fun landingPointDot(density: Float): BitmapDescriptor {
    val size = (8 * density).toInt()
    val bitmap = createBitmap(size, size)
    val radius = size / 2f - density
    Canvas(bitmap).apply {
        drawCircle(size / 2f, size / 2f, radius, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = android.graphics.Color.argb(230, 255, 255, 255) })
        drawCircle(
            size / 2f,
            size / 2f,
            radius,
            Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = density
                color = android.graphics.Color.argb(128, 0, 0, 0)
            },
        )
    }
    return BitmapDescriptorFactory.fromBitmap(bitmap)
}
