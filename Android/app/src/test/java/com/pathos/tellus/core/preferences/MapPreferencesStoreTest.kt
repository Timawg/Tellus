package com.pathos.tellus.core.preferences

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class MapPreferencesStoreTest {

    @get:Rule
    val folder = TemporaryFolder()

    private fun TestScope.makeStore(): MapPreferencesStore {
        val file = folder.newFile("prefs.preferences_pb").also { it.delete() }
        val dataStore = PreferenceDataStoreFactory.create(
            scope = backgroundScope,
        ) { file }
        return MapPreferencesStore(dataStore)
    }

    @Test
    fun layersUseIosDefaultsWhenNothingIsStored() = runTest {
        val store = makeStore()
        for (layer in MapLayer.entries) {
            assertEquals(layer.name, layer.defaultEnabled, store.isEnabled(layer).first())
        }
        assertTrue(store.isEnabled(MapLayer.FLIGHTS).first())
        assertTrue(store.isEnabled(MapLayer.HAZARDS).first())
        assertFalse(store.isEnabled(MapLayer.AURORA).first())
    }

    @Test
    fun layerToggleRoundTripsWithoutAffectingOtherLayers() = runTest {
        val store = makeStore()
        store.setEnabled(MapLayer.FLIGHTS, false)
        store.setEnabled(MapLayer.AURORA, true)

        assertFalse(store.isEnabled(MapLayer.FLIGHTS).first())
        assertTrue(store.isEnabled(MapLayer.AURORA).first())
        assertTrue(store.isEnabled(MapLayer.HAZARDS).first())
    }

    @Test
    fun nationalityRoundTripsAndClears() = runTest {
        val store = makeStore()
        assertNull(store.nationalityJson.first())

        store.setNationalityJson("""{"cca2":"SE"}""")
        assertEquals("""{"cca2":"SE"}""", store.nationalityJson.first())

        store.setNationalityJson(null)
        assertNull(store.nationalityJson.first())
    }

    @Test
    fun keysMatchIos() {
        assertEquals(
            listOf(
                "showsFlights", "showsHazards", "showsCables", "showsPowerGrid",
                "showsEarthAtNight", "showsAurora", "showsGPSJAM", "showsVIIRSImagery",
            ),
            MapLayer.entries.map { it.key },
        )
    }
}
