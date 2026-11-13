package com.pathos.tellus.map

import kotlin.math.PI
import kotlin.math.atan
import kotlin.math.cos
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sinh
import kotlin.math.sqrt
import kotlin.math.tan

/** A latitude and longitude in degrees. Kept free of Maps SDK types so the geometry is unit-testable. */
data class Coordinate(val latitude: Double, val longitude: Double)

/**
 * A point in Web Mercator scaled so the world is a 1×1 square, x growing east
 * from 180°W and y growing south from the top. This is MapKit's `MKMapPoint`
 * divided by the world size, so the iOS geometry ports unchanged.
 */
data class MercatorPoint(val x: Double, val y: Double) {
    val coordinate: Coordinate
        get() = Coordinate(
            latitude = Math.toDegrees(atan(sinh(PI * (1 - 2 * y)))),
            longitude = x * 360 - 180,
        )

    companion object {
        // The latitude where Web Mercator's square world ends.
        private const val MAX_LATITUDE = 85.05112878

        fun of(coordinate: Coordinate): MercatorPoint {
            val latitude = Math.toRadians(coordinate.latitude.coerceIn(-MAX_LATITUDE, MAX_LATITUDE))
            return MercatorPoint(
                x = (coordinate.longitude + 180) / 360,
                y = (1 - ln(tan(latitude) + 1 / cos(latitude)) / PI) / 2,
            )
        }

        /** World widths per metre at [latitude], like `MKMapPointsPerMeterAtLatitude` over the world width. */
        fun perMetre(latitude: Double): Double =
            1 / (EARTH_CIRCUMFERENCE_METRES * cos(Math.toRadians(latitude)))

        private const val EARTH_CIRCUMFERENCE_METRES = 40_075_016.686
    }
}

/** An axis-aligned rect in [MercatorPoint] space. Like `MKMapRect`, it may run past the world's edges. */
data class MercatorRect(val minX: Double, val minY: Double, val maxX: Double, val maxY: Double) {
    val width get() = maxX - minX
    val height get() = maxY - minY
    val area get() = width * height
    val midX get() = (minX + maxX) / 2
    val midY get() = (minY + maxY) / 2

    fun contains(point: MercatorPoint) =
        point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY

    fun offsetBy(dx: Double) = MercatorRect(minX + dx, minY, maxX + dx, maxY)

    fun union(other: MercatorRect) =
        MercatorRect(min(minX, other.minX), min(minY, other.minY), max(maxX, other.maxX), max(maxY, other.maxY))

    /** Gap between two rects; 0 when they touch or overlap. */
    fun distanceTo(other: MercatorRect): Double {
        val dx = max(0.0, max(minX - other.maxX, other.minX - maxX))
        val dy = max(0.0, max(minY - other.maxY, other.minY - maxY))
        return sqrt(dx * dx + dy * dy)
    }
}
