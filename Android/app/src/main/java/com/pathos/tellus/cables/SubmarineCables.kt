package com.pathos.tellus.cables

import com.pathos.tellus.map.Coordinate
import com.pathos.tellus.map.MercatorPoint
import com.pathos.tellus.map.MercatorRect
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.JsonPrimitive
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/** An undersea cable's route, from TeleGeography's Submarine Cable Map. Ported from iOS `SubmarineCable`. */
data class SubmarineCable(
    val id: String,
    val name: String,
    /** TeleGeography's colour for the cable, e.g. "#939597". */
    val colorHex: String,
    /** The route, split where it branches or crosses the 180° meridian. */
    val lines: List<List<Coordinate>>,
)

/** A place where cables come ashore, e.g. "Cork, Ireland". */
data class CableLandingPoint(val id: String, val name: String, val coordinate: Coordinate)

/** Details shown when a cable is tapped. */
@Serializable
data class CableDetails(
    val id: String,
    val name: String,
    val length: String? = null,
    val owners: String? = null,
    val suppliers: String? = null,
    @SerialName("rfs_year") val rfsYear: Int? = null,
    @SerialName("is_planned") val isPlanned: Boolean? = null,
    val url: String? = null,
    @SerialName("landing_points") val landingPoints: List<LandingPoint> = emptyList(),
) {
    @Serializable
    data class LandingPoint(val id: String, val name: String, val country: String? = null)

    /** The cable's page on submarinecablemap.com. */
    val mapUrl: String get() = "https://www.submarinecablemap.com/submarine-cable/$id"

    /** Landing points grouped by country, countries sorted by name. */
    val landingPointsByCountry: List<Pair<String, List<LandingPoint>>>
        get() = landingPoints.groupBy { it.country ?: "Other" }.toSortedMap().toList()
}

/** The cable and landing point files are GeoJSON feature collections. */
@Serializable
internal data class CableGeoJson(val features: List<Feature>) {

    @Serializable
    data class Feature(val properties: Properties, val geometry: Geometry)

    @Serializable
    data class Properties(val id: String, val name: String, val color: String? = null)

    /** `[[[lon, lat]]]` for a MultiLineString, `[lon, lat]` for a Point. */
    @Serializable
    data class Geometry(val coordinates: JsonElement)

    /** One cable per id; a cable can be split over several features. */
    val cables: List<SubmarineCable>
        get() {
            val byId = linkedMapOf<String, SubmarineCable>()
            for (feature in features) {
                val lines = feature.geometry.multiLine() ?: continue
                val coordinates = lines.map { line -> line.mapNotNull(::coordinate) }.filter { it.size >= 2 }
                val id = feature.properties.id
                val cable = byId[id] ?: SubmarineCable(id, feature.properties.name, feature.properties.color ?: DEFAULT_COLOR, emptyList())
                byId[id] = cable.copy(lines = cable.lines + coordinates)
            }
            return byId.values.toList()
        }

    val landingPoints: List<CableLandingPoint>
        get() = features.mapNotNull { feature ->
            val coordinate = feature.geometry.point()?.let(::coordinate) ?: return@mapNotNull null
            CableLandingPoint(feature.properties.id, feature.properties.name, coordinate)
        }

    // Not private: the serialization plugin adds `serializer()` to this companion.
    companion object {
        private const val DEFAULT_COLOR = "#939597"

        private fun Geometry.multiLine(): List<List<JsonElement>>? {
            val lines = coordinates as? JsonArray ?: return null
            if (lines.any { it !is JsonArray || it.any { pair -> pair !is JsonArray } }) return null
            return lines.map { it as JsonArray }
        }

        private fun Geometry.point(): JsonElement? = (coordinates as? JsonArray)?.takeIf { pair -> pair.none { it is JsonArray } }

        private fun coordinate(pair: JsonElement): Coordinate? {
            val values = (pair as? JsonArray)?.map { (it as? JsonPrimitive)?.doubleOrNull } ?: return null
            if (values.size < 2) return null
            val longitude = values[0] ?: return null
            val latitude = values[1] ?: return null
            return Coordinate(latitude, longitude)
        }
    }
}

/**
 * Cable routes and landing points projected to [MercatorPoint] space once, so
 * taps and map tiles don't reproject thousands of points each time. Tap
 * tests port iOS `CableMapLayer.nearestCableID` and `CableOverlay.distance(to:)`;
 * tolerances are fractions of the world's width.
 */
class CableGeometry(cables: List<SubmarineCable>, landingPoints: List<CableLandingPoint>) {

    class Route(val cable: SubmarineCable, val lines: List<List<MercatorPoint>>, val bounds: MercatorRect)

    class Point(val landingPoint: CableLandingPoint, val position: MercatorPoint)

    val routes: List<Route> = cables.map { cable ->
        val lines = cable.lines.map { line -> line.map(MercatorPoint::of) }
        val points = lines.flatten()
        Route(
            cable,
            lines,
            MercatorRect(
                points.minOfOrNull { it.x } ?: 0.0,
                points.minOfOrNull { it.y } ?: 0.0,
                points.maxOfOrNull { it.x } ?: 0.0,
                points.maxOfOrNull { it.y } ?: 0.0,
            ),
        )
    }

    val points: List<Point> = landingPoints.map { Point(it, MercatorPoint.of(it.coordinate)) }

    fun nearestCableId(point: MercatorPoint, tolerance: Double): String? {
        val area = MercatorRect(point.x - tolerance, point.y - tolerance, point.x + tolerance, point.y + tolerance)
        return routes
            .filter { it.bounds.distanceTo(area) == 0.0 }
            .map { it.cable.id to distance(point, it) }
            .filter { it.second <= tolerance }
            .minByOrNull { it.second }
            ?.first
    }

    fun nearestLandingPoint(point: MercatorPoint, tolerance: Double): CableLandingPoint? =
        points
            .map { it to hypot(it.position.x - point.x, it.position.y - point.y) }
            .filter { it.second <= tolerance }
            .minByOrNull { it.second }
            ?.first
            ?.landingPoint

    private fun distance(point: MercatorPoint, route: Route): Double {
        var nearest = Double.POSITIVE_INFINITY
        for (line in route.lines) {
            for (index in 0 until line.size - 1) {
                nearest = min(nearest, distance(point, line[index], line[index + 1]))
            }
        }
        return nearest
    }

    private fun distance(p: MercatorPoint, a: MercatorPoint, b: MercatorPoint): Double {
        val dx = b.x - a.x
        val dy = b.y - a.y
        val lengthSquared = dx * dx + dy * dy
        val t = if (lengthSquared == 0.0) 0.0 else max(0.0, min(1.0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        val x = a.x + t * dx - p.x
        val y = a.y + t * dy - p.y
        return sqrt(x * x + y * y)
    }
}

/**
 * The landing points to draw in one map tile. MapKit hides annotations that
 * would overlap; tiles can't ask the map, so a dot is skipped when an
 * earlier one, in feed order, lies within [spacing].
 */
fun visibleLandingPoints(points: List<CableGeometry.Point>, tile: MercatorRect, spacing: Double): List<CableGeometry.Point> {
    val cells = HashMap<Long, MutableList<MercatorPoint>>()
    val shown = mutableListOf<CableGeometry.Point>()
    // Consider points just outside the tile too, so neighbouring tiles
    // mostly agree on dots near their shared edge.
    val area = MercatorRect(tile.minX - spacing, tile.minY - spacing, tile.maxX + spacing, tile.maxY + spacing)
    fun key(x: Long, y: Long) = (x shl 32) xor (y and 0xFFFFFFFFL)
    for (point in points) {
        val position = point.position
        if (!area.contains(position)) continue
        val cellX = floor(position.x / spacing).toLong()
        val cellY = floor(position.y / spacing).toLong()
        val crowded = (-1L..1L).any { dx ->
            (-1L..1L).any { dy ->
                cells[key(cellX + dx, cellY + dy)]?.any { hypot(it.x - position.x, it.y - position.y) < spacing } == true
            }
        }
        if (crowded) continue
        cells.getOrPut(key(cellX, cellY)) { mutableListOf() } += position
        shown += point
    }
    return shown
}

/** "#RRGGBB" as an opaque ARGB int, or null when it isn't one. */
internal fun parseHexColor(hex: String): Int? {
    val digits = hex.removePrefix("#")
    if (digits.length != 6) return null
    val value = digits.toIntOrNull(16) ?: return null
    return (0xFF shl 24) or value
}
