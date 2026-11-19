package com.pathos.tellus.cables

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.pathos.tellus.core.preferences.MapLayer
import com.pathos.tellus.core.preferences.MapPreferencesStore
import com.pathos.tellus.map.MercatorPoint
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class CableLayerUiState(
    val isEnabled: Boolean = false,
    /** Null while the layer is off or loading. */
    val dataset: CableDataset? = null,
    val selectedId: String? = null,
    /** The landing point whose name is showing, like iOS's callout. */
    val selectedLandingPoint: CableLandingPoint? = null,
    /** Null while the selected cable's details load, or when they couldn't be loaded. */
    val selectedDetails: CableDetails? = null,
    /**
     * The details request failed. iOS shows "Loading details…" until the
     * sheet closes; here the sheet says so and offers a retry instead.
     */
    val detailsFailed: Boolean = false,
) {
    val selected: SubmarineCable? get() = dataset?.cables?.firstOrNull { it.id == selectedId }
}

/**
 * The undersea cables layer, ported from iOS `CableLayerModel`. The dataset
 * loads once when the layer turns on and is kept while the app runs; it isn't
 * polled. A load or details response that arrives after the layer turns off,
 * or after another cable is selected, is dropped.
 */
@HiltViewModel
class CableLayerViewModel @Inject constructor(
    private val service: CableService,
    private val preferences: MapPreferencesStore,
) : ViewModel() {

    private val _state = MutableStateFlow(CableLayerUiState())
    val state: StateFlow<CableLayerUiState> = _state.asStateFlow()

    private var dataset: CableDataset? = null
    private var loadJob: Job? = null
    private var detailsJob: Job? = null

    init {
        viewModelScope.launch {
            if (preferences.isEnabled(MapLayer.CABLES).first()) enable()
        }
    }

    fun setEnabled(enabled: Boolean) {
        if (enabled == _state.value.isEnabled) return
        viewModelScope.launch { preferences.setEnabled(MapLayer.CABLES, enabled) }
        if (enabled) {
            enable()
        } else {
            loadJob?.cancel()
            loadJob = null
            select(null)
            _state.update { it.copy(isEnabled = false, dataset = null, selectedLandingPoint = null) }
        }
    }

    fun select(id: String?) {
        val state = _state.value
        if (id == state.selectedId || (id != null && !state.isEnabled)) return
        _state.update { it.copy(selectedId = id) }
        loadDetails(id)
    }

    fun retryDetails() {
        val id = _state.value.selectedId ?: return
        if (_state.value.detailsFailed) loadDetails(id)
    }

    private fun loadDetails(id: String?) {
        detailsJob?.cancel()
        _state.update { it.copy(selectedDetails = null, detailsFailed = false) }
        if (id == null) return
        detailsJob = viewModelScope.launch {
            val details = loadOrNull { service.getDetails(id) }
            // Cancelling the job on a new selection already drops a stale
            // response; the check guards one that completed in between.
            if (_state.value.selectedId == id) _state.update { it.copy(selectedDetails = details, detailsFailed = details == null) }
        }
    }

    /**
     * Handles a map tap at [point], with tolerances in world widths. A
     * landing point shows its name, as its annotation takes the tap on iOS;
     * otherwise the nearest cable is selected. Returns false when the tap
     * hit neither, so the map can select the country there.
     */
    fun tap(point: MercatorPoint, cableTolerance: Double, landingPointTolerance: Double): Boolean {
        val geometry = _state.value.dataset?.geometry
        val landingPoint = geometry?.nearestLandingPoint(point, landingPointTolerance)
        _state.update { it.copy(selectedLandingPoint = landingPoint) }
        if (landingPoint != null) return true
        val cableId = geometry?.nearestCableId(point, cableTolerance) ?: return false
        select(cableId)
        return true
    }

    private fun enable() {
        _state.update { it.copy(isEnabled = true) }
        dataset?.let { show(it); return }
        loadJob = viewModelScope.launch {
            val loaded = loadOrNull { service.getCables() } ?: return@launch
            dataset = loaded
            if (_state.value.isEnabled) show(loaded)
        }
    }

    private fun show(dataset: CableDataset) {
        _state.update { it.copy(dataset = dataset) }
    }

    private suspend fun <T> loadOrNull(load: suspend () -> T): T? = try {
        load()
    } catch (error: CancellationException) {
        throw error
    } catch (_: Exception) {
        null
    }
}
