package com.pathos.tellus.map

import kotlin.math.log2
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/** Where to point the camera: a centre and how much of the world's height to show. */
data class MapFit(val center: Coordinate, val mercatorHeight: Double) {
    /**
     * The Google Maps zoom that shows [mercatorHeight] in a map
     * [viewportHeightDp] tall. At zoom z the world is 256·2^z dp across.
     */
    fun zoom(viewportHeightDp: Float): Float =
        log2(viewportHeightDp / (WORLD_SIZE_DP_AT_ZOOM_0 * mercatorHeight)).toFloat()

    private companion object {
        const val WORLD_SIZE_DP_AT_ZOOM_0 = 256.0
    }
}

/** Ports iOS `MapRegionCalculator` and `MKCoordinateRegion(fitting:aspectRatio:)`. */
object MapRegionCalculator {

    /**
     * A fit showing [fullRect] inside the part of the screen the map's
     * floating controls leave free: below the country card and above the
     * bottom controls. [aspectRatio] is the map's width over height. Handles
     * rects that run past the 180° meridian.
     */
    fun fitting(fullRect: MercatorRect, aspectRatio: Double): MapFit {
        // Mercator stretches the poles, so Arctic islands (Franz Josef Land,
        // northern Greenland) would take up most of the view. Fit only up
        // to 72° north and south; the outline still draws beyond.
        val polarLimit = MercatorPoint.of(Coordinate(72.0, 0.0)).y
        val minY = max(fullRect.minY, polarLimit)
        val maxY = min(fullRect.maxY, 1 - polarLimit)
        val rect = if (maxY > minY) MercatorRect(fullRect.minX, minY, fullRect.maxX, maxY) else fullRect

        // Fractions of the screen height, from the top, between which the
        // country should sit, and the side margin.
        val freeTop = 0.34
        val freeBottom = 0.76
        val sideMargin = 0.06

        // Very small countries (Vatican, Monaco) still show their
        // surroundings: at least about 30 km across.
        val center = MercatorPoint(rect.midX, rect.midY)
        val minimumWidth = 30_000 * MercatorPoint.perMetre(center.coordinate.latitude)

        // Fit the height in the free band, and the width across the screen,
        // but don't zoom out more than 1.6 times the height fit for width
        // alone: on a portrait screen Russia or Canada would otherwise shrink
        // to a sliver, so they run off the sides instead.
        val heightFit = rect.height / (freeBottom - freeTop)
        val widthFit = rect.width / (1 - sideMargin * 2) / aspectRatio
        var height = max(heightFit, min(widthFit, heightFit * 1.6))
        // Near the poles the map can't scroll past the edge of the world, so
        // zooming out further would push the country off its free band.
        // Stop where it can still sit there.
        val bandCentre = (freeTop + freeBottom) / 2
        val roomAbove = rect.midY / bandCentre
        val roomBelow = (1 - rect.midY) / (1 - bandCentre)
        height = max(heightFit, minOf(height, roomAbove, roomBelow))
        height = min(max(height, minimumWidth / aspectRatio), 1.0)

        // Put the country's middle at the middle of the free band, keeping
        // the view inside the world for countries too big to fit.
        var centerY = rect.midY - (bandCentre - 0.5) * height
        centerY = centerY.coerceIn(height / 2, 1 - height / 2)
        var centerX = rect.midX % 1.0
        if (centerX < 0) centerX += 1.0
        return MapFit(MercatorPoint(centerX, centerY.coerceIn(0.0, 1.0)).coordinate, height)
    }

    /**
     * A rough fit for a country without an outline, from its area in km² and
     * its centre, as iOS `MapRegionCalculator.region(for:)` does.
     */
    fun fitting(area: Double?, latlng: List<Double>, aspectRatio: Double): MapFit? {
        if (area == null || !area.isFinite() || area <= 0 || latlng.size < 2) return null
        val center = Coordinate(latlng[0], latlng[1])
        if (center.latitude !in -90.0..90.0 || center.longitude !in -180.0..180.0) return null
        val latitudeDelta = sqrt(area) / 110
        val top = MercatorPoint.of(Coordinate(center.latitude + latitudeDelta / 2, 0.0)).y
        val bottom = MercatorPoint.of(Coordinate(center.latitude - latitudeDelta / 2, 0.0)).y
        // MapKit shows the whole requested span, so the wider of the two wins.
        val width = latitudeDelta * 2 / 360
        return MapFit(center, min(max(bottom - top, width / aspectRatio), 1.0))
    }
}
