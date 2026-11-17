package com.pathos.tellus.flights

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.pathos.tellus.core.network.HttpError
import com.pathos.tellus.core.preferences.MapLayer
import com.pathos.tellus.core.preferences.MapPreferencesStore
import com.pathos.tellus.map.MapRegionCalculator
import com.pathos.tellus.map.MercatorRect
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.time.Clock
import java.time.Instant
import javax.inject.Inject

data class LiveFlightsUiState(
    val showsFlights: Boolean = false,
    /** The aircraft to draw; at most [LiveFlightsViewModel.MAX_VISIBLE_FLIGHTS]. */
    val markers: List<FlightMarker> = emptyList(),
    /** Every flight in view, before sampling. */
    val totalFlightCount: Int = 0,
    /** OpenSky is rate limiting us until then. */
    val pausedUntil: Instant? = null,
    /** Latest data per aircraft, by ICAO address, for the details sheet. */
    val flights: Map<String, LiveFlight> = emptyMap(),
    val selection: Selection? = null,
    val selectedAircraft: AircraftInfo? = null,
    val selectedRoute: FlightRoute? = null,
    val isLoadingDetails: Boolean = false,
) {
    /** A tap on an aircraft. [request] tells two taps on the same aircraft apart. */
    data class Selection(val id: String, val request: Long)

    val isShowingSubsetOfFlights: Boolean get() = markers.size < totalFlightCount
}

/**
 * Live aircraft on the map, ported from iOS `LiveFlightsModel`. It polls
 * every 15 seconds while the map is on screen, the layer is on and the
 * camera is still, and draws at most 500 aircraft spread across the view.
 */
@HiltViewModel
class LiveFlightsViewModel @Inject constructor(
    private val flightService: FlightService,
    private val detailsService: FlightDetailsService,
    private val preferences: MapPreferencesStore,
    private val clock: Clock,
) : ViewModel() {

    private val _state = MutableStateFlow(LiveFlightsUiState())
    val state: StateFlow<LiveFlightsUiState> = _state.asStateFlow()

    private var viewport: MercatorRect? = null
    private var isMapActive = false
    private var isViewportChanging = false
    private var pollJob: Job? = null
    private var detailsJob: Job? = null
    private var lastOpenSkyFlights: List<LiveFlight> = emptyList()
    private var selectionCount = 0L

    init {
        viewModelScope.launch {
            val shows = preferences.isEnabled(MapLayer.FLIGHTS).first()
            _state.update { it.copy(showsFlights = shows) }
            startPollingIfNeeded()
        }
    }

    fun setShowsFlights(shows: Boolean) {
        if (shows == _state.value.showsFlights) return
        viewModelScope.launch { preferences.setEnabled(MapLayer.FLIGHTS, shows) }
        _state.update { it.copy(showsFlights = shows) }
        if (shows) {
            startPollingIfNeeded()
        } else {
            stopPolling()
            select(null)
            lastOpenSkyFlights = emptyList()
            _state.update { it.copy(markers = emptyList(), flights = emptyMap(), totalFlightCount = 0, pausedUntil = null) }
        }
    }

    /** Polling runs only while the map is on screen. */
    fun setMapActive(active: Boolean) {
        isMapActive = active
        if (active) startPollingIfNeeded() else stopPolling()
    }

    /** The camera started moving; a poll for the old view would be wasted. */
    fun viewportWillChange() {
        isViewportChanging = true
        stopPolling()
    }

    fun updateViewport(rect: MercatorRect) {
        isViewportChanging = false
        if (viewport != rect) {
            stopPolling()
            viewport = rect
        }
        startPollingIfNeeded()
    }

    /** Selects an aircraft (or clears the selection) and loads its details. */
    fun select(id: String?) {
        val current = _state.value.selection
        if (id == current?.id) return
        detailsJob?.cancel()
        val selection = id?.let { LiveFlightsUiState.Selection(it, ++selectionCount) }
        _state.update {
            it.copy(
                selection = selection,
                selectedAircraft = if (selection == null) it.selectedAircraft else null,
                selectedRoute = if (selection == null) it.selectedRoute else null,
                isLoadingDetails = selection != null,
            )
        }
        if (selection != null) detailsJob = viewModelScope.launch { loadDetails(selection) }
    }

    private suspend fun loadDetails(request: LiveFlightsUiState.Selection) = coroutineScope {
        val callsign = _state.value.flights[request.id]?.callsign.orEmpty()
        // Both lookups belong to this selection's job, so a new selection cancels them.
        val aircraft = async { loadOrNull { detailsService.getAircraft(request.id) } }
        val route = if (callsign.isEmpty()) null else loadOrNull { detailsService.getRoute(callsign) }

        if (_state.value.selection != request) return@coroutineScope
        val position = _state.value.flights[request.id]?.coordinate
        if (route != null && position != null && route.isPlausible(position)) {
            _state.update { it.copy(selectedRoute = route) }
        }

        val loadedAircraft = aircraft.await()
        // Another aircraft may have been selected while loading.
        if (_state.value.selection != request) return@coroutineScope
        _state.update { it.copy(selectedAircraft = loadedAircraft, isLoadingDetails = false) }
    }

    private fun startPollingIfNeeded() {
        val rect = viewport ?: return
        if (!isMapActive || !_state.value.showsFlights || isViewportChanging || pollJob != null) return
        pollJob = viewModelScope.launch {
            while (isActive) {
                poll(rect)
                delay(POLL_INTERVAL_MS)
            }
        }
    }

    private fun stopPolling() {
        pollJob?.cancel()
        pollJob = null
    }

    private suspend fun poll(rect: MercatorRect) = coroutineScope {
        val (latitudes, longitudes) = MapRegionCalculator.bounds(rect)
        val military = async { loadOrNull { flightService.getMilitaryFlights() } }
        val openSky = try {
            Result.success(
                flightService.getFlights(
                    CoordinateSpan(latitudes.start, latitudes.endInclusive),
                    CoordinateSpan(longitudes.start, longitudes.endInclusive),
                ),
            )
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            Result.failure(error)
        }
        val militaryFlights = military.await()

        openSky.onSuccess { flights ->
            lastOpenSkyFlights = flights
            _state.update { it.copy(pausedUntil = null) }
        }.onFailure { error ->
            if (error is HttpError.RateLimited) {
                val until = error.retryAfterSeconds?.let { clock.instant().plusMillis((it * 1000).toLong()) }
                _state.update { it.copy(pausedUntil = until) }
            }
        }

        val militaryInView = militaryFlights.orEmpty().filter {
            it.coordinate.latitude in latitudes && it.coordinate.longitude in longitudes
        }
        val byId = LinkedHashMap<String, LiveFlight>()
        for (flight in lastOpenSkyFlights.merging(militaryInView)) byId.putIfAbsent(flight.id, flight)
        val sample = byId.values.map(FlightMarker::from).distributed(rect, MAX_VISIBLE_FLIGHTS, _state.value.selection?.id)
        _state.update {
            it.copy(
                flights = byId,
                totalFlightCount = sample.visibleCount,
                markers = if (it.markers == sample.markers) it.markers else sample.markers,
            )
        }
    }

    private suspend fun <T> loadOrNull(load: suspend () -> T): T? = try {
        load()
    } catch (error: CancellationException) {
        throw error
    } catch (_: Exception) {
        null
    }

    companion object {
        const val POLL_INTERVAL_MS = 15_000L

        // Google Maps, like MapKit, starts to stutter beyond a few hundred moving markers.
        const val MAX_VISIBLE_FLIGHTS = 500
    }
}
