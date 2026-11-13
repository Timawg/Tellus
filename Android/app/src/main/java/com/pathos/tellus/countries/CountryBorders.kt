package com.pathos.tellus.countries

import android.content.Context
import com.pathos.tellus.core.coroutines.DefaultDispatcher
import com.pathos.tellus.map.Coordinate
import com.pathos.tellus.map.MercatorPoint
import com.pathos.tellus.map.MercatorRect
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.double
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import javax.inject.Inject

/** A closed ring of a polygon, in both coordinates (for drawing) and Mercator points (for hit-testing). */
class Ring(val coordinates: List<Coordinate>) {
    private val xs = DoubleArray(coordinates.size)
    private val ys = DoubleArray(coordinates.size)
    val bounds: MercatorRect

    init {
        coordinates.forEachIndexed { index, coordinate ->
            val point = MercatorPoint.of(coordinate)
            xs[index] = point.x
            ys[index] = point.y
        }
        bounds = MercatorRect(
            minX = xs.minOrNull() ?: 0.0,
            minY = ys.minOrNull() ?: 0.0,
            maxX = xs.maxOrNull() ?: 0.0,
            maxY = ys.maxOrNull() ?: 0.0,
        )
    }

    /** Even-odd ray casting, as in iOS `CountryBorder.ring(_:count:contains:)`. */
    fun contains(point: MercatorPoint): Boolean {
        val count = xs.size
        if (count < 3) return false
        var inside = false
        var j = count - 1
        for (i in 0 until count) {
            if ((ys[i] > point.y) != (ys[j] > point.y) &&
                point.x < (xs[j] - xs[i]) * (point.y - ys[i]) / (ys[j] - ys[i]) + xs[i]
            ) {
                inside = !inside
            }
            j = i
        }
        return inside
    }
}

/** One piece of a country: an outer ring minus any holes (lakes, enclaves such as Lesotho). */
class BorderPolygon(val outer: Ring, val holes: List<Ring>) {
    val bounds: MercatorRect get() = outer.bounds

    fun contains(point: MercatorPoint): Boolean =
        outer.contains(point) && holes.none { it.contains(point) }
}

/**
 * A country's outline, from the bundled Natural Earth borders
 * (country-borders.geojson, built by scripts/build_country_borders.py).
 */
class CountryBorder(
    /** ISO 3166-1 alpha-3, as in the country list. */
    val cca3: String,
    val polygons: List<BorderPolygon>,
) {
    /** Rough size of the whole country: the summed bounding areas of its pieces. */
    val totalArea: Double = polygons.sumOf { it.bounds.area }

    /**
     * The part of the country to zoom to: its largest piece and the pieces
     * that belong with it, leaving out far-off territories such as French
     * Guiana or Hawaii. See [focusRect].
     */
    val focusRect: MercatorRect? get() = focusRect(polygons.map { it.bounds })

    /** The bounding area of this country's piece that contains [point], or null if it's outside. */
    fun areaOfPieceContaining(point: MercatorPoint): Double? =
        polygons
            .filter { it.bounds.contains(point) && it.contains(point) }
            .minOfOrNull { it.bounds.area }

    companion object {
        /**
         * Grows a cluster from the largest piece. A piece joins when it's
         * within one anchor-size of a piece already in, and either sizeable (at
         * least 2% of the anchor's area) or right next to it, so specks of
         * islands far out don't widen the view. Pieces across the 180°
         * meridian are shifted next to the rest, so the rect can extend past
         * the edge of the world.
         */
        fun focusRect(rects: List<MercatorRect>): MercatorRect? {
            val anchor = rects.maxByOrNull { it.area } ?: return null
            // Shift each piece by a world width when that brings it closer to
            // the anchor, so Chukotka sits next to the rest of Russia.
            val pieces = rects.map { rect ->
                val dx = rect.midX - anchor.midX
                when {
                    dx > 0.5 -> rect.offsetBy(-1.0)
                    dx < -0.5 -> rect.offsetBy(1.0)
                    else -> rect
                }
            }
            val reach = maxOf(anchor.width, anchor.height)
            val anchorArea = anchor.area

            val included = mutableListOf(anchor)
            val remaining = pieces.toMutableList()
            var grew = true
            while (grew) {
                grew = false
                val iterator = remaining.iterator()
                while (iterator.hasNext()) {
                    val piece = iterator.next()
                    val gap = included.minOf { piece.distanceTo(it) }
                    val isSizeable = piece.area >= anchorArea * 0.02
                    if (gap <= reach * 0.05 || (isSizeable && gap <= reach)) {
                        included += piece
                        iterator.remove()
                        grew = true
                    }
                }
            }
            return included.reduce { union, rect -> union.union(rect) }
        }
    }
}

object CountryBorders {

    /**
     * The alpha-3 code of the country at [coordinate]. Where outlines overlap
     * the smallest piece wins, and between identical pieces (Réunion is drawn
     * both on its own and as part of France) the smaller country, so tapping
     * an overseas territory picks the territory.
     */
    fun countryAt(coordinate: Coordinate, borders: Map<String, CountryBorder>): String? {
        val point = MercatorPoint.of(coordinate)
        return borders.values
            .mapNotNull { border -> border.areaOfPieceContaining(point)?.let { Triple(border.cca3, it, border.totalArea) } }
            .minWithOrNull(compareBy({ it.second }, { it.third }))
            ?.first
    }

    /**
     * Every country with an outline, by alpha-3 code. Features without a
     * `cca3` or without polygon geometry are skipped, as on iOS.
     */
    fun parse(geoJson: String): Map<String, CountryBorder> {
        val features = Json.parseToJsonElement(geoJson).jsonObject["features"]?.jsonArray ?: return emptyMap()
        val borders = mutableMapOf<String, CountryBorder>()
        for (feature in features) {
            val featureObject = feature as? JsonObject ?: continue
            val code = (featureObject["properties"] as? JsonObject)?.get("cca3")?.jsonPrimitive?.content ?: continue
            val geometry = featureObject["geometry"] as? JsonObject ?: continue
            val coordinates = geometry["coordinates"] as? JsonArray ?: continue
            val polygons = when (geometry["type"]?.jsonPrimitive?.content) {
                "Polygon" -> listOf(polygon(coordinates))
                "MultiPolygon" -> coordinates.map { polygon(it.jsonArray) }
                else -> emptyList()
            }
            if (polygons.isNotEmpty()) borders[code] = CountryBorder(code, polygons)
        }
        return borders
    }

    private fun polygon(rings: JsonArray): BorderPolygon {
        val parsed = rings.map { ring ->
            Ring(ring.jsonArray.map { position ->
                val pair = position.jsonArray
                // GeoJSON positions are longitude first.
                Coordinate(latitude = pair[1].jsonPrimitive.double, longitude = pair[0].jsonPrimitive.double)
            })
        }
        return BorderPolygon(outer = parsed.first(), holes = parsed.drop(1))
    }
}

/** Loads the bundled borders. Decoding takes a moment, so it runs off the main thread. */
interface CountryBordersLoader {
    suspend fun load(): Map<String, CountryBorder>
}

class AssetCountryBordersLoader @Inject constructor(
    @param:ApplicationContext private val context: Context,
    @param:DefaultDispatcher private val dispatcher: CoroutineDispatcher,
) : CountryBordersLoader {

    override suspend fun load(): Map<String, CountryBorder> = withContext(dispatcher) {
        val text = context.assets.open("country-borders.geojson").bufferedReader().use { it.readText() }
        CountryBorders.parse(text)
    }
}
