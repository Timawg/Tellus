package com.pathos.tellus.core.preferences

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

/** Map layers the user can toggle. Keys match the iOS `MapLayer` raw values. */
enum class MapLayer(val key: String, val defaultEnabled: Boolean) {
    FLIGHTS("showsFlights", defaultEnabled = true),
    HAZARDS("showsHazards", defaultEnabled = true),
    CABLES("showsCables", defaultEnabled = false),
    POWER_GRID("showsPowerGrid", defaultEnabled = false),
    EARTH_AT_NIGHT("showsEarthAtNight", defaultEnabled = false),
    AURORA("showsAurora", defaultEnabled = false),
    GPS_JAM("showsGPSJAM", defaultEnabled = false),
    VIIRS_IMAGERY("showsVIIRSImagery", defaultEnabled = false),
}

/**
 * Layer toggles and the user's nationality, mirroring iOS `MapPreferencesStore`.
 * The iOS-only legacy keys (`showsDayNight`, `showsNightLights`) aren't read,
 * since there is no earlier Android data to migrate.
 */
@Singleton
class MapPreferencesStore @Inject constructor(
    private val dataStore: DataStore<Preferences>,
) {
    fun isEnabled(layer: MapLayer): Flow<Boolean> =
        dataStore.data
            .map { it[booleanPreferencesKey(layer.key)] ?: layer.defaultEnabled }
            .distinctUntilChanged()

    suspend fun setEnabled(layer: MapLayer, enabled: Boolean) {
        dataStore.edit { it[booleanPreferencesKey(layer.key)] = enabled }
    }

    /**
     * The nationality as the JSON-encoded country, as iOS stores it. Kept as a
     * string until the Country model exists; callers decode it.
     */
    val nationalityJson: Flow<String?> =
        dataStore.data
            .map { it[NATIONALITY] }
            .distinctUntilChanged()

    suspend fun setNationalityJson(json: String?) {
        dataStore.edit { preferences ->
            if (json == null) preferences.remove(NATIONALITY) else preferences[NATIONALITY] = json
        }
    }

    private companion object {
        val NATIONALITY = stringPreferencesKey("nationality")
    }
}
