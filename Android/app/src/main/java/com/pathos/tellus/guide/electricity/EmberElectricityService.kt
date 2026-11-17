package com.pathos.tellus.guide.electricity

import com.pathos.tellus.core.coroutines.DefaultDispatcher
import com.pathos.tellus.core.network.NetworkService
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import okhttp3.Request
import java.io.File
import java.io.IOException
import java.time.Clock
import java.time.Duration
import java.time.Instant
import javax.inject.Inject
import javax.inject.Qualifier
import javax.inject.Singleton

@Serializable
data class CountryElectricityProfile(
    val year: Int,
    val totalGenerationTWh: Double,
    val netImportsTWh: Double? = null,
    val fuels: List<Fuel>,
) {
    @Serializable
    data class Fuel(val name: String, val generationTWh: Double, val sharePercent: Double? = null)

    companion object {
        const val SOURCE_URL = "https://ember-energy.org/data/yearly-electricity-data/"
    }
}

interface ElectricityService {
    suspend fun getProfile(countryCode: String): CountryElectricityProfile?
}

/** Where the Ember snapshot is cached on disk. */
@Qualifier
@Retention(AnnotationRetention.BINARY)
annotation class EmberCacheFile

/**
 * Ember's yearly electricity data. One global CSV serves every country; the
 * parsed profiles are cached on disk for 7 days in the same file name iOS
 * uses, and the last snapshot is kept when a refresh fails.
 */
@Singleton
class EmberElectricityService @Inject constructor(
    private val networkService: NetworkService,
    private val json: Json,
    private val clock: Clock,
    @param:EmberCacheFile private val cacheFile: File?,
    @param:DefaultDispatcher private val parseDispatcher: CoroutineDispatcher,
) : ElectricityService {

    @Serializable
    private data class Snapshot(val fetchedAtMillis: Long, val profiles: Map<String, CountryElectricityProfile>)

    // Refreshes run here rather than in the caller, so a closing view doesn't
    // cancel the download for other callers or discard the new cache. It
    // lives as long as this singleton, which is the app process.
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val mutex = Mutex()
    private var snapshot: Snapshot? = null
    private var refresh: Deferred<Snapshot>? = null

    override suspend fun getProfile(countryCode: String): CountryElectricityProfile? {
        val input = countryCode.uppercase()
        if (input.length != 3 || !input.all { it in 'A'..'Z' }) return null
        // Tellus's country dataset uses UNK for Kosovo. Ember uses XKX.
        val code = if (input == "UNK") "XKX" else input
        val task = mutex.withLock {
            refresh?.let { return@withLock it }
            if (snapshot == null) snapshot = readCache()
            snapshot?.let { current ->
                val age = Duration.between(Instant.ofEpochMilli(current.fetchedAtMillis), clock.instant())
                if (age < LIFETIME) return current.profiles[code]
            }
            scope.async { refreshNow() }.also { refresh = it }
        }
        return task.await().profiles[code]
    }

    private suspend fun refreshNow(): Snapshot {
        try {
            val request = Request.Builder().url("$ROOT_URL/release_generation_yearly_global.csv").build()
            val text = networkService.send(request).decodeToString()
            val profiles = withContext(parseDispatcher) { EmberElectricityDataset.profiles(text) }
            val fresh = Snapshot(clock.instant().toEpochMilli(), profiles)
            mutex.withLock {
                snapshot = fresh
                refresh = null
            }
            writeCache(fresh)
            return fresh
        } catch (error: Exception) {
            return mutex.withLock {
                refresh = null
                snapshot ?: throw error
            }
        }
    }

    private suspend fun readCache(): Snapshot? = withContext(Dispatchers.IO) {
        try {
            cacheFile?.takeIf { it.exists() }?.let { json.decodeFromString<Snapshot>(it.readText()) }
        } catch (_: IOException) {
            null
        } catch (_: IllegalArgumentException) {
            null
        }
    }

    private suspend fun writeCache(fresh: Snapshot) = withContext(Dispatchers.IO) {
        val file = cacheFile ?: return@withContext
        try {
            // Write then rename, so a crash never leaves a half-written cache.
            val temporary = File(file.parentFile, file.name + ".tmp")
            temporary.writeText(json.encodeToString(Snapshot.serializer(), fresh))
            temporary.renameTo(file)
        } catch (_: IOException) {
        }
    }

    private companion object {
        const val ROOT_URL = "https://files.ember-energy.org/public-downloads/generation/outputs"
        val LIFETIME: Duration = Duration.ofDays(7)
    }
}

/** Parses Ember's yearly CSV into each country's latest profile, as iOS `EmberElectricityDataset` does. */
object EmberElectricityDataset {

    private class Observations {
        var total: Double? = null
        var imports: Double? = null
        val fuels = mutableListOf<CountryElectricityProfile.Fuel>()
    }

    fun profiles(contents: String): Map<String, CountryElectricityProfile> {
        val lines = contents.lineSequence().filter { it.isNotEmpty() }.iterator()
        if (!lines.hasNext()) throw SerializationException("Empty Ember CSV")
        val header = fields(lines.next()).map { value(it).trim('﻿') }
        fun column(name: String) = header.indexOf(name).takeIf { it >= 0 } ?: throw SerializationException("No $name column")
        val codeColumn = column("ISO 3 code")
        val yearColumn = column("Year")
        val sourceColumn = column("Electricity source")
        val aggregateColumn = column("Is aggregated source")
        val generationColumn = column("Generation (TWh)")
        val shareColumn = column("Share of generation (%)")

        val observations = mutableMapOf<String, MutableMap<Int, Observations>>()
        while (lines.hasNext()) {
            val row = fields(lines.next())
            if (row.size != header.size || row[codeColumn].length != 3) continue
            val year = row[yearColumn].toIntOrNull() ?: continue
            val generation = row[generationColumn].toDoubleOrNull()?.takeIf { it.isFinite() } ?: continue
            val source = value(row[sourceColumn])
            val entry = { observations.getOrPut(row[codeColumn]) { mutableMapOf() }.getOrPut(year) { Observations() } }
            when {
                source == "Total generation" && generation >= 0 -> entry().total = generation
                source == "Net imports" -> entry().imports = generation
                row[aggregateColumn] == "False" && generation > 0 && source.isNotEmpty() -> {
                    val share = row[shareColumn].toDoubleOrNull()?.takeIf { it.isFinite() && it >= 0 }
                    entry().fuels += CountryElectricityProfile.Fuel(source, generation, share)
                }
            }
        }

        val profiles = observations.mapNotNull { (code, years) ->
            val (year, latest) = years.filter { it.value.total != null }.maxByOrNull { it.key } ?: return@mapNotNull null
            code to CountryElectricityProfile(
                year = year,
                totalGenerationTWh = latest.total!!,
                netImportsTWh = latest.imports,
                fuels = latest.fuels.sortedByDescending { it.generationTWh },
            )
        }.toMap()
        if (profiles.isEmpty()) throw SerializationException("No Ember profiles")
        return profiles
    }

    private fun fields(row: String): List<String> {
        if ('"' !in row) return row.split(',')
        val fields = mutableListOf<String>()
        var start = 0
        var quoted = false
        row.forEachIndexed { index, char ->
            when {
                char == '"' -> quoted = !quoted
                char == ',' && !quoted -> {
                    fields += row.substring(start, index)
                    start = index + 1
                }
            }
        }
        fields += row.substring(start)
        return fields
    }

    private fun value(field: String): String =
        if (field.length >= 2 && field.first() == '"' && field.last() == '"') {
            field.substring(1, field.length - 1).replace("\"\"", "\"")
        } else {
            field
        }
}
