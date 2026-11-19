package com.pathos.tellus.cables

import com.pathos.tellus.core.coroutines.DefaultDispatcher
import com.pathos.tellus.core.network.NetworkService
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.DeserializationStrategy
import kotlinx.serialization.json.Json
import okhttp3.Request
import javax.inject.Inject
import javax.inject.Singleton

/** Every cable route and landing point. */
data class CableDataset(val cables: List<SubmarineCable>, val landingPoints: List<CableLandingPoint>) {
    /** Projected when the dataset is built, which the service does off the main thread. */
    val geometry = CableGeometry(cables, landingPoints)
}

interface CableService {
    suspend fun getCables(): CableDataset

    /** Length, owners and landing points for one cable. */
    suspend fun getDetails(cableId: String): CableDetails
}

/**
 * Undersea cables from TeleGeography's Submarine Cable Map, which serves its
 * data without a key. The files change rarely and are sent with a 2 hour
 * max-age and an ETag, so the app's OkHttp disk cache keeps them between
 * launches and revalidates cheaply, like the shared URL cache on iOS.
 * Ported from iOS `CableService`.
 */
@Singleton
class SubmarineCableMapService @Inject constructor(
    private val networkService: NetworkService,
    private val json: Json,
    @param:DefaultDispatcher private val parseDispatcher: CoroutineDispatcher,
) : CableService {

    private val mutex = Mutex()
    private var dataset: CableDataset? = null
    private val details = mutableMapOf<String, CableDetails>()

    override suspend fun getCables(): CableDataset {
        mutex.withLock { dataset }?.let { return it }
        val result = coroutineScope {
            val routes = async { fetch("/cable/cable-geo.json", CableGeoJson.serializer()) }
            val points = async { fetch("/landing-point/landing-point-geo.json", CableGeoJson.serializer()) }
            val routeFile = routes.await()
            val pointFile = points.await()
            // About 2,000 route segments and 2,000 landing points, so map and project them off the main thread.
            withContext(parseDispatcher) { CableDataset(routeFile.cables, pointFile.landingPoints) }
        }
        mutex.withLock { dataset = result }
        return result
    }

    override suspend fun getDetails(cableId: String): CableDetails {
        // The id goes into the path, so only TeleGeography's slug characters are allowed.
        require(cableId.isNotEmpty() && cableId.all { it.code < 128 && (it.isLetterOrDigit() || it == '-') }) { "Invalid cable id" }
        mutex.withLock { details[cableId] }?.let { return it }
        val result = fetch("/cable/$cableId.json", CableDetails.serializer())
        mutex.withLock { details[cableId] = result }
        return result
    }

    private suspend fun <T> fetch(path: String, deserializer: DeserializationStrategy<T>): T {
        val request = Request.Builder().url("$ROOT_URL$path").build()
        val body = networkService.send(request)
        return withContext(parseDispatcher) { json.decodeFromString(deserializer, body.decodeToString()) }
    }

    private companion object {
        const val ROOT_URL = "https://www.submarinecablemap.com/api/v3"
    }
}
