package com.pathos.tellus.cables

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import com.pathos.tellus.core.preferences.MapLayer
import com.pathos.tellus.core.preferences.MapPreferencesStore
import com.pathos.tellus.map.Coordinate
import com.pathos.tellus.map.MercatorPoint
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
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
class CableLayerViewModelTest {

    @get:Rule
    val folder = TemporaryFolder()

    private val dispatcher = StandardTestDispatcher()

    @Before
    fun setUp() = Dispatchers.setMain(dispatcher)

    @After
    fun tearDown() = Dispatchers.resetMain()

    private val cable = SubmarineCable("ak-link", "AK-Link", "#939597", listOf(listOf(Coordinate(10.0, -10.0), Coordinate(10.0, 10.0))))
    private val other = SubmarineCable("2africa", "2Africa", "#ff0000", listOf(listOf(Coordinate(-10.0, -10.0), Coordinate(-10.0, 10.0))))
    private val dataset = CableDataset(listOf(cable, other), listOf(CableLandingPoint("cork", "Cork", Coordinate(51.9, -8.47))))

    /** Each call waits for the test to complete the matching deferred, so it controls ordering. */
    private class FakeCables : CableService {
        var cables = CompletableDeferred<CableDataset>()
        val details = mutableMapOf<String, CompletableDeferred<CableDetails>>()
        var loads = 0

        override suspend fun getCables(): CableDataset {
            loads++
            return cables.await()
        }

        override suspend fun getDetails(cableId: String) = details.getOrPut(cableId) { CompletableDeferred() }.await()
    }

    private fun TestScope.preferences(): MapPreferencesStore {
        val file = folder.newFile("prefs.preferences_pb").also { it.delete() }
        return MapPreferencesStore(PreferenceDataStoreFactory.create(scope = backgroundScope) { file })
    }

    @Test
    fun offByDefaultAndLoadsOnceWhenTurnedOn() = runTest(dispatcher) {
        val service = FakeCables().apply { cables.complete(dataset) }
        val preferences = preferences()
        val viewModel = CableLayerViewModel(service, preferences)
        runCurrent()
        assertFalse(viewModel.state.value.isEnabled)
        assertEquals(0, service.loads)

        viewModel.setEnabled(true)
        runCurrent()
        assertEquals(listOf("ak-link", "2africa"), viewModel.state.value.dataset?.cables?.map { it.id })
        assertEquals(1, viewModel.state.value.dataset?.landingPoints?.size)
        assertTrue(preferences.isEnabled(MapLayer.CABLES).first())

        viewModel.setEnabled(false)
        viewModel.setEnabled(true)
        runCurrent()
        assertEquals(1, service.loads)
        assertEquals(2, viewModel.state.value.dataset?.cables?.size)
    }

    @Test
    fun startsOnWhenSavedOn() = runTest(dispatcher) {
        val service = FakeCables().apply { cables.complete(dataset) }
        val preferences = preferences()
        preferences.setEnabled(MapLayer.CABLES, true)
        val viewModel = CableLayerViewModel(service, preferences)
        runCurrent()

        assertTrue(viewModel.state.value.isEnabled)
        assertEquals(2, viewModel.state.value.dataset?.cables?.size)
    }

    @Test
    fun aLoadFinishingAfterTheLayerTurnsOffIsDropped() = runTest(dispatcher) {
        val service = FakeCables()
        val viewModel = CableLayerViewModel(service, preferences())
        runCurrent()
        viewModel.setEnabled(true)
        runCurrent()
        viewModel.setEnabled(false)
        service.cables.complete(dataset)
        runCurrent()

        assertFalse(viewModel.state.value.isEnabled)
        assertNull(viewModel.state.value.dataset)
    }

    @Test
    fun aFailedLoadIsRetriedWhenTurnedOnAgain() = runTest(dispatcher) {
        val service = FakeCables().apply { cables.completeExceptionally(IOException("down")) }
        val viewModel = CableLayerViewModel(service, preferences())
        runCurrent()
        viewModel.setEnabled(true)
        runCurrent()
        assertNull(viewModel.state.value.dataset)

        service.cables = CompletableDeferred(dataset)
        viewModel.setEnabled(false)
        viewModel.setEnabled(true)
        runCurrent()
        assertEquals(2, service.loads)
        assertEquals(2, viewModel.state.value.dataset?.cables?.size)
    }

    @Test
    fun detailsForAnEarlierSelectionAreDropped() = runTest(dispatcher) {
        val service = FakeCables().apply { cables.complete(dataset) }
        val viewModel = CableLayerViewModel(service, preferences())
        runCurrent()
        viewModel.setEnabled(true)
        runCurrent()

        viewModel.select("ak-link")
        runCurrent()
        viewModel.select("2africa")
        runCurrent()
        service.details.getValue("ak-link").complete(CableDetails("ak-link", "AK-Link"))
        runCurrent()
        assertEquals("2africa", viewModel.state.value.selected?.id)
        assertNull(viewModel.state.value.selectedDetails)

        service.details.getValue("2africa").complete(CableDetails("2africa", "2Africa", length = "45,000 km"))
        runCurrent()
        assertEquals("45,000 km", viewModel.state.value.selectedDetails?.length)
    }

    @Test
    fun failedDetailsCanBeRetried() = runTest(dispatcher) {
        val service = FakeCables().apply { cables.complete(dataset) }
        val viewModel = CableLayerViewModel(service, preferences())
        runCurrent()
        viewModel.setEnabled(true)
        runCurrent()
        viewModel.select("ak-link")
        runCurrent()
        service.details.remove("ak-link")!!.completeExceptionally(IOException("down"))
        runCurrent()
        assertTrue(viewModel.state.value.detailsFailed)
        assertNull(viewModel.state.value.selectedDetails)

        viewModel.retryDetails()
        runCurrent()
        assertFalse(viewModel.state.value.detailsFailed)
        service.details.getValue("ak-link").complete(CableDetails("ak-link", "AK-Link"))
        runCurrent()
        assertEquals("AK-Link", viewModel.state.value.selectedDetails?.name)
        assertFalse(viewModel.state.value.detailsFailed)
    }

    @Test
    fun aTapOnALandingPointShowsItsNameInsteadOfSelectingACable() = runTest(dispatcher) {
        val service = FakeCables().apply { cables.complete(dataset) }
        val viewModel = CableLayerViewModel(service, preferences())
        runCurrent()
        viewModel.setEnabled(true)
        runCurrent()

        assertTrue(viewModel.tap(MercatorPoint.of(Coordinate(51.9, -8.47)), 0.001, 0.0005))
        assertEquals("cork", viewModel.state.value.selectedLandingPoint?.id)
        assertNull(viewModel.state.value.selectedId)

        // A tap elsewhere hides the name and falls through to the country.
        assertFalse(viewModel.tap(MercatorPoint.of(Coordinate(40.0, 40.0)), 0.001, 0.0005))
        assertNull(viewModel.state.value.selectedLandingPoint)
    }

    @Test
    fun turningOffClearsTheSelectionAndStopsHitTesting() = runTest(dispatcher) {
        val service = FakeCables().apply { cables.complete(dataset) }
        val viewModel = CableLayerViewModel(service, preferences())
        runCurrent()
        viewModel.setEnabled(true)
        runCurrent()
        val nearAkLink = MercatorPoint.of(Coordinate(10.05, 0.0))
        assertTrue(viewModel.tap(nearAkLink, 0.001, 0.0005))
        runCurrent()
        assertEquals("ak-link", viewModel.state.value.selectedId)

        viewModel.setEnabled(false)
        runCurrent()
        assertNull(viewModel.state.value.selectedId)
        assertFalse(viewModel.tap(nearAkLink, 0.001, 0.0005))
        // Selecting while off is ignored, as on iOS.
        viewModel.select("ak-link")
        assertNull(viewModel.state.value.selectedId)
    }
}
