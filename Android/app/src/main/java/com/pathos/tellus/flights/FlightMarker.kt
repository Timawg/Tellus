package com.pathos.tellus.flights

import com.pathos.tellus.map.Coordinate
import com.pathos.tellus.map.MercatorPoint
import com.pathos.tellus.map.MercatorRect
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/** What the map needs to draw one aircraft. */
data class FlightMarker(
    val id: String,
    val latitude: Double,
    val longitude: Double,
    val track: Float?,
    val source: LiveFlight.Source,
) {
    val coordinate: Coordinate get() = Coordinate(latitude, longitude)

    companion object {
        fun from(flight: LiveFlight) = FlightMarker(
            id = flight.id,
            latitude = flight.coordinate.latitude,
            longitude = flight.coordinate.longitude,
            track = flight.track?.toFloat(),
            source = flight.source,
        )
    }
}

/** The markers to draw and how many flights were in view. */
data class FlightSample(val markers: List<FlightMarker>, val visibleCount: Int)

/**
 * Samples occupied cells across the viewport, reserving a place for the
 * selected flight if it is visible. All visible flights fit below the limit.
 * Ported from iOS `Array<FlightMarker>.distributed(in:limit:keeping:)`, in the
 * same Mercator space.
 */
fun List<FlightMarker>.distributed(rect: MercatorRect, limit: Int, keeping: String? = null): FlightSample {
    if (!rect.minX.isFinite() || !rect.minY.isFinite() || !(rect.width > 0) || !(rect.height > 0)) return FlightSample(emptyList(), 0)

    val width = min(rect.width, 1.0)
    data class Placed(val marker: FlightMarker, val x: Double, val y: Double)

    val visible = mapNotNull { marker ->
        if (marker.latitude !in -90.0..90.0 || marker.longitude !in -180.0..180.0) return@mapNotNull null
        val point = MercatorPoint.of(marker.coordinate)
        // Measure east from the viewport's left edge, wrapping at the date line.
        val offset = (point.x - rect.minX) % 1.0
        val x = if (offset < 0) offset + 1.0 else offset
        val y = point.y - rect.minY
        if (x !in 0.0..width || y !in 0.0..rect.height) null else Placed(marker, x, y)
    }

    if (limit <= 0) return FlightSample(emptyList(), visible.size)
    if (visible.size <= limit) return FlightSample(visible.map { it.marker }, visible.size)

    // Use at most one cell per available slot, with roughly square cells in
    // map coordinates. Every occupied cell can then contribute a marker.
    val aspectRatio = min(limit.toDouble(), max(1.0 / limit, width / rect.height))
    val columns = max(1, sqrt(limit * aspectRatio).toInt())
    val rows = limit / columns
    val cells = List(rows * columns) { mutableListOf<FlightMarker>() }
    for ((marker, x, y) in visible) {
        val column = min(columns - 1, (x / width * columns).toInt())
        val row = min(rows - 1, (y / rect.height * rows).toInt())
        cells[row * columns + column] += marker
    }

    val occupied = cells.filter { it.isNotEmpty() }.map { cell ->
        ArrayDeque(cell.sortedWith(compareBy<FlightMarker> { it.id != keeping }.thenBy { it.id }))
    }.toMutableList()
    val sample = ArrayList<FlightMarker>(limit)
    while (sample.size < limit && occupied.isNotEmpty()) {
        val slots = min(limit - sample.size, occupied.size)
        // Spread a partial round across the remaining occupied cells too.
        for (slot in 0 until slots) {
            val index = ((slot + 0.5) * occupied.size / slots).toInt()
            occupied[index].removeFirstOrNull()?.let(sample::add)
        }
        occupied.removeAll { it.isEmpty() }
    }
    return FlightSample(sample, visible.size)
}
