package com.pathos.tellus.guide.democracy

import android.content.Context
import com.pathos.tellus.guide.profile.AnnualObservation
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import javax.inject.Inject
import javax.inject.Singleton

data class DemocracyProfile(val version: Int, val series: List<Series>) {
    data class Series(val id: String, val area: String?, val observations: List<AnnualObservation>)
}

/** The bundled V-Dem Electoral Democracy Index (vdem-democracy.json, built by scripts/build_vdem_democracy.py). */
@Serializable
data class DemocracyDataset(val version: Int, val countries: Map<String, List<Observation>>) {

    @Serializable
    data class Observation(val year: Int, val value: Double)

    fun profile(countryCode: String?): DemocracyProfile {
        val code = countryCode?.uppercase()
        val series = when {
            // V-Dem reports these as distinct areas.
            code == "PSE" -> listOfNotNull(series("PSE", "West Bank"), series("PSG", "Gaza"))
            code != null -> listOfNotNull(series(if (code == "UNK") "XKX" else code))
            else -> emptyList()
        }
        return DemocracyProfile(version, series)
    }

    private fun series(code: String, area: String? = null): DemocracyProfile.Series? {
        val observations = countries[code]?.takeIf { it.isNotEmpty() } ?: return null
        return DemocracyProfile.Series(code, area, observations.map { AnnualObservation(it.year, it.value) })
    }
}

interface DemocracyProfiles {
    suspend fun profile(countryCode: String?): DemocracyProfile
}

/** Decodes the bundled dataset once, on first use. */
@Singleton
class AssetDemocracyDatasetStore @Inject constructor(
    @param:ApplicationContext private val context: Context,
    private val json: Json,
) : DemocracyProfiles {
    private val mutex = Mutex()
    private var dataset: DemocracyDataset? = null

    override suspend fun profile(countryCode: String?): DemocracyProfile {
        val loaded = mutex.withLock {
            dataset ?: withContext(Dispatchers.IO) {
                val text = context.assets.open("vdem-democracy.json").bufferedReader().use { it.readText() }
                json.decodeFromString<DemocracyDataset>(text)
            }.also { dataset = it }
        }
        return loaded.profile(countryCode)
    }
}
