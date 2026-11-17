package com.pathos.tellus.hazards

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import com.pathos.tellus.core.preferences.MapLayer
import com.pathos.tellus.core.preferences.MapPreferencesStore
import com.pathos.tellus.map.Coordinate
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.IOException

@OptIn(ExperimentalCoroutinesApi::class)
class HazardLayerViewModelTest {

    @get:Rule
    val folder = TemporaryFolder()

    private val dispatcher = StandardTestDispatcher()

    @Before
    fun setUp() = Dispatchers.setMain(dispatcher)

    @After
    fun tearDown() = Dispatchers.resetMain()

    private fun hazard(id: String, kind: DisasterAlert.Kind) = NaturalHazard(
        id, kind, id, Coordinate(15.0, 130.0), NaturalHazard.Severity.MODERATE, null, null, null, null, null, null,
        false, null, null, NaturalHazard.Source.GDACS, null, 1L to 1L,
    )

    private class FakeHazards(val hazards: List<NaturalHazard>) : HazardService {
        var loads = 0
        var fail = false
        override suspend fun getHazards(): List<NaturalHazard> {
            loads++
            if (fail) throw IOException("down")
            return hazards
        }
        override suspend fun getTrack(cyclone: NaturalHazard) = CycloneTrack(cyclone.id, cyclone.severity, listOf(listOf(cyclone.coordinate, cyclone.coordinate)), emptyList())
    }

    private fun TestScope.preferences(): MapPreferencesStore {
        val file = folder.newFile("prefs.preferences_pb").also { it.delete() }
        return MapPreferencesStore(PreferenceDataStoreFactory.create(scope = backgroundScope) { file })
    }

    private val sample = listOf(hazard("cyclone", DisasterAlert.Kind.CYCLONE), hazard("flood", DisasterAlert.Kind.FLOOD))

    @Test
    fun refreshesEveryFifteenMinutesWhileOnScreenWithCycloneTracks() = runTest(dispatcher) {
        val service = FakeHazards(sample)
        val viewModel = HazardLayerViewModel(service, preferences())
        runCurrent()
        viewModel.setMapActive(true)
        runCurrent()

        assertTrue(viewModel.state.value.isEnabled)
        assertEquals(listOf("cyclone", "flood"), viewModel.state.value.hazards.map { it.id })
        assertEquals(listOf("cyclone"), viewModel.state.value.tracks.map { it.hazardId })
        advanceTimeBy(15 * 60 * 1000L + 1)
        assertEquals(2, service.loads)

        viewModel.setMapActive(false)
        advanceTimeBy(60 * 60 * 1000L)
        assertEquals(2, service.loads)
    }

    @Test
    fun failedRefreshKeepsWhatIsShown() = runTest(dispatcher) {
        val service = FakeHazards(sample)
        val viewModel = HazardLayerViewModel(service, preferences())
        runCurrent()
        viewModel.setMapActive(true)
        runCurrent()
        service.fail = true
        advanceTimeBy(15 * 60 * 1000L + 1)
        assertEquals(2, viewModel.state.value.hazards.size)
        viewModel.setMapActive(false)
    }

    @Test
    fun turningTheLayerOffClearsSelectionAndIsSaved() = runTest(dispatcher) {
        val preferences = preferences()
        val viewModel = HazardLayerViewModel(FakeHazards(sample), preferences)
        runCurrent()
        viewModel.setMapActive(true)
        runCurrent()
        viewModel.select("flood")
        assertEquals("flood", viewModel.state.value.selected?.id)

        viewModel.setEnabled(false)
        runCurrent()
        assertTrue(viewModel.state.value.hazards.isEmpty())
        assertNull(viewModel.state.value.selected)
        assertFalse(preferences.isEnabled(MapLayer.HAZARDS).first())
    }
}
