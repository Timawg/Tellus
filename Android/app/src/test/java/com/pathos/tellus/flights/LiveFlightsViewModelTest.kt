package com.pathos.tellus.flights

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import com.pathos.tellus.core.network.HttpError
import com.pathos.tellus.core.preferences.MapLayer
import com.pathos.tellus.core.preferences.MapPreferencesStore
import com.pathos.tellus.map.Coordinate
import com.pathos.tellus.map.MercatorPoint
import com.pathos.tellus.map.MercatorRect
import com.pathos.tellus.testing.MutableClock
import kotlinx.coroutines.CompletableDeferred
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
import java.time.Instant

@OptIn(ExperimentalCoroutinesApi::class)
class LiveFlightsViewModelTest {

    @get:Rule
    val folder = TemporaryFolder()

    private val dispatcher = StandardTestDispatcher()

    @Before
    fun setUp() = Dispatchers.setMain(dispatcher)

    @After
    fun tearDown() = Dispatchers.resetMain()

    private val clock = MutableClock(Instant.parse("2026-11-17T12:00:00Z"))

    private fun flight(id: String, callsign: String? = null) = LiveFlight(
        id, callsign, Coordinate(57.0, 12.0), 90.0, 10_000.0, false, 200.0, 0.0, null, "Sweden", null, null, null,
        Instant.EPOCH, LiveFlight.Source.OPEN_SKY,
    )

    private class FakeFlights : FlightService {
        var polls = 0
        var result: () -> List<LiveFlight> = { emptyList() }
        override suspend fun getFlights(latitudeSpan: CoordinateSpan?, longitudeSpan: CoordinateSpan?): List<LiveFlight> {
            polls++
            return result()
        }
        override suspend fun getMilitaryFlights() = emptyList<LiveFlight>()
    }

    private class FakeDetails : FlightDetailsService {
        val aircraft = mutableMapOf<String, CompletableDeferred<AircraftInfo?>>()
        override suspend fun getAircraft(icao24: String) = aircraft.getOrPut(icao24) { CompletableDeferred() }.await()
        override suspend fun getRoute(callsign: String): FlightRoute? = null
    }

    private fun TestScope.preferences(): MapPreferencesStore {
        val file = folder.newFile("prefs.preferences_pb").also { it.delete() }
        return MapPreferencesStore(PreferenceDataStoreFactory.create(scope = backgroundScope) { file })
    }

    private val sweden: MercatorRect = run {
        val topLeft = MercatorPoint.of(Coordinate(70.0, 5.0))
        val bottomRight = MercatorPoint.of(Coordinate(50.0, 25.0))
        MercatorRect(topLeft.x, topLeft.y, bottomRight.x, bottomRight.y)
    }

    private fun TestScope.activeViewModel(flights: FakeFlights, details: FakeDetails = FakeDetails(), preferences: MapPreferencesStore = preferences()) =
        LiveFlightsViewModel(flights, details, preferences, clock).also {
            runCurrent()
            it.setMapActive(true)
            it.updateViewport(sweden)
            runCurrent()
        }

    @Test
    fun pollsEveryFifteenSecondsWhileActive() = runTest(dispatcher) {
        val flights = FakeFlights().apply { result = { listOf(flight("4acb58")) } }
        val viewModel = activeViewModel(flights)

        assertEquals(1, flights.polls)
        assertEquals(listOf("4acb58"), viewModel.state.value.markers.map { it.id })
        advanceTimeBy(15_001)
        assertEquals(2, flights.polls)

        viewModel.setMapActive(false)
        advanceTimeBy(60_000)
        assertEquals(2, flights.polls)
    }

    @Test
    fun turningTheLayerOffStopsPollingClearsAircraftAndIsSaved() = runTest(dispatcher) {
        val flights = FakeFlights().apply { result = { listOf(flight("4acb58")) } }
        val preferences = preferences()
        val viewModel = activeViewModel(flights, preferences = preferences)

        viewModel.setShowsFlights(false)
        runCurrent()
        advanceTimeBy(60_000)

        assertEquals(1, flights.polls)
        assertTrue(viewModel.state.value.markers.isEmpty())
        assertFalse(preferences.isEnabled(MapLayer.FLIGHTS).first())
    }

    @Test
    fun movingCameraPausesPollingUntilItSettles() = runTest(dispatcher) {
        val flights = FakeFlights()
        val viewModel = activeViewModel(flights)
        viewModel.viewportWillChange()
        advanceTimeBy(60_000)
        assertEquals(1, flights.polls)

        viewModel.updateViewport(sweden)
        runCurrent()
        assertEquals(2, flights.polls)
        viewModel.stop()
    }

    @Test
    fun rateLimitShowsWhenFlightsResume() = runTest(dispatcher) {
        val flights = FakeFlights().apply { result = { throw HttpError.RateLimited(120.0) } }
        val viewModel = activeViewModel(flights)
        assertEquals(clock.now.plusSeconds(120), viewModel.state.value.pausedUntil)

        flights.result = { emptyList() }
        advanceTimeBy(15_001)
        assertNull(viewModel.state.value.pausedUntil)
        viewModel.stop()
    }

    @Test
    fun lateDetailsForAnEarlierSelectionAreDropped() = runTest(dispatcher) {
        val flights = FakeFlights().apply { result = { listOf(flight("a", "SAS1"), flight("b", "SAS2")) } }
        val details = FakeDetails()
        val viewModel = activeViewModel(flights, details)

        viewModel.select("a")
        runCurrent()
        viewModel.select("b")
        runCurrent()
        details.aircraft.getValue("a").complete(AircraftInfo(registration = "SE-AAA"))
        runCurrent()
        assertNull(viewModel.state.value.selectedAircraft)
        assertTrue(viewModel.state.value.isLoadingDetails)

        details.aircraft.getValue("b").complete(AircraftInfo(registration = "SE-BBB"))
        runCurrent()
        assertEquals("SE-BBB", viewModel.state.value.selectedAircraft?.registration)
        assertFalse(viewModel.state.value.isLoadingDetails)
        viewModel.stop()
    }

    /**
     * The poll loop never ends on its own, and runTest would keep advancing
     * virtual time through it at the end of a test, so tests stop it.
     */
    private fun LiveFlightsViewModel.stop() = setMapActive(false)
}
