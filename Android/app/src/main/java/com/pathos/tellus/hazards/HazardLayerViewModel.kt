package com.pathos.tellus.hazards

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.pathos.tellus.core.preferences.MapLayer
import com.pathos.tellus.core.preferences.MapPreferencesStore
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import javax.inject.Inject

data class HazardLayerUiState(
    val isEnabled: Boolean = false,
    val hazards: List<NaturalHazard> = emptyList(),
    val tracks: List<CycloneTrack> = emptyList(),
    /** The hazard whose sheet is open, kept as it was when tapped while the feed refreshes. */
    val selected: NaturalHazard? = null,
)

/**
 * The natural hazards layer, ported from iOS `HazardLayerModel`. It refreshes
 * every 15 minutes while the layer is on and the map is on screen.
 */
@HiltViewModel
class HazardLayerViewModel @Inject constructor(
    private val service: HazardService,
    private val preferences: MapPreferencesStore,
) : ViewModel() {

    private val _state = MutableStateFlow(HazardLayerUiState())
    val state: StateFlow<HazardLayerUiState> = _state.asStateFlow()

    private var isMapActive = false
    private var refreshJob: Job? = null

    init {
        viewModelScope.launch {
            _state.update { it.copy(isEnabled = preferences.isEnabled(MapLayer.HAZARDS).first()) }
            startIfNeeded()
        }
    }

    fun setEnabled(enabled: Boolean) {
        if (enabled == _state.value.isEnabled) return
        viewModelScope.launch { preferences.setEnabled(MapLayer.HAZARDS, enabled) }
        _state.update { it.copy(isEnabled = enabled) }
        if (enabled) {
            startIfNeeded()
        } else {
            stop()
            _state.update { it.copy(hazards = emptyList(), tracks = emptyList(), selected = null) }
        }
    }

    /** Refreshing runs only while the map is on screen. */
    fun setMapActive(active: Boolean) {
        isMapActive = active
        if (active) startIfNeeded() else stop()
    }

    fun select(id: String?) {
        _state.update { state -> state.copy(selected = id?.let { selected -> state.hazards.firstOrNull { it.id == selected } }) }
    }

    private fun startIfNeeded() {
        if (!isMapActive || !_state.value.isEnabled || refreshJob != null) return
        refreshJob = viewModelScope.launch {
            while (isActive) {
                refresh()
                delay(REFRESH_INTERVAL_MS)
            }
        }
    }

    private fun stop() {
        refreshJob?.cancel()
        refreshJob = null
    }

    private suspend fun refresh() {
        val loaded = loadOrNull { service.getHazards() } ?: return
        if (loaded != _state.value.hazards) _state.update { it.copy(hazards = loaded) }
        val tracks = loaded.filter { it.kind == DisasterAlert.Kind.CYCLONE }.mapNotNull { loadOrNull { service.getTrack(it) } }
        if (tracks != _state.value.tracks) _state.update { it.copy(tracks = tracks) }
    }

    private suspend fun <T> loadOrNull(load: suspend () -> T): T? = try {
        load()
    } catch (error: CancellationException) {
        throw error
    } catch (_: Exception) {
        null
    }

    companion object {
        const val REFRESH_INTERVAL_MS = 15 * 60 * 1000L
    }
}
