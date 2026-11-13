package com.pathos.tellus.map

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.pathos.tellus.countries.CountriesService
import com.pathos.tellus.countries.Country
import com.pathos.tellus.countries.CountryBorder
import com.pathos.tellus.countries.CountryBorders
import com.pathos.tellus.countries.CountryBordersLoader
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.text.Collator
import javax.inject.Inject
import kotlin.random.Random

/** Where the camera should go for the selected country. */
sealed interface CameraTarget {
    fun fit(aspectRatio: Double): MapFit?

    /** Fit the country's outline between the country card and the bottom controls. */
    data class Outline(val rect: MercatorRect) : CameraTarget {
        override fun fit(aspectRatio: Double) = MapRegionCalculator.fitting(rect, aspectRatio)
    }

    /** No outline (a few tiny territories): a zoom based on the country's area. */
    data class Area(val area: Double?, val latlng: List<Double>) : CameraTarget {
        override fun fit(aspectRatio: Double) = MapRegionCalculator.fitting(area, latlng, aspectRatio)
    }
}

/** A request to move the camera. [id] grows with each request, so the screen can tell them apart. */
data class CameraRequest(val id: Long, val target: CameraTarget)

data class MainMapUiState(
    /** Sorted by common name, so the list is easy to scan. */
    val countries: List<Country> = emptyList(),
    val current: Country? = null,
    /** The selected country's outline; null when it isn't in the bundled borders. */
    val selectedBorder: CountryBorder? = null,
    val cameraRequest: CameraRequest? = null,
    val loadFailed: Boolean = false,
)

/** Country selection and the map region, ported from iOS `MainMapViewModel`. */
@HiltViewModel
class MainMapViewModel @Inject constructor(
    private val countriesService: CountriesService,
    private val bordersLoader: CountryBordersLoader,
    private val random: Random,
) : ViewModel() {

    private val _state = MutableStateFlow(MainMapUiState())
    val state: StateFlow<MainMapUiState> = _state.asStateFlow()

    private var destinationJob: Job? = null
    private var cameraRequestCount = 0L

    // Decoded once, on first use. A failed load counts as no borders, as on iOS.
    private val borders: Deferred<Map<String, CountryBorder>> =
        viewModelScope.async(start = CoroutineStart.LAZY) {
            try {
                bordersLoader.load()
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                emptyMap()
            }
        }

    init {
        retrieveCountries()
    }

    fun retrieveCountries() {
        viewModelScope.launch {
            try {
                val collator = Collator.getInstance()
                val loaded = countriesService.getAllCountries().sortedWith(
                    compareBy(collator) { it.name?.common.orEmpty() }
                )
                _state.update { it.copy(countries = loaded, loadFailed = false) }
                selectRandomCountry()
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                _state.update { it.copy(loadFailed = true) }
            }
        }
    }

    /** Countries sharing a border with [country], in list order. */
    fun neighbours(of: Country): List<Country> {
        val codes = of.borders.orEmpty().toSet()
        return _state.value.countries.filter { it.cca3 in codes }
    }

    fun dismissLoadError() {
        _state.update { it.copy(loadFailed = false) }
    }

    fun selectRandomCountry() {
        _state.value.countries.randomOrNull(random)?.let(::select)
    }

    fun select(country: Country) {
        if (country.cca3 == _state.value.current?.cca3) return
        _state.update { it.copy(current = country) }
        destinationJob?.cancel()
        destinationJob = viewModelScope.launch { updateRegion(country) }
    }

    /**
     * Selects the country under a tap on the map. Taps on the sea, or on the
     * selected country, do nothing. [onSelected] runs when the selection
     * changes, for feedback such as a haptic tick.
     */
    fun selectCountryAt(coordinate: Coordinate, onSelected: () -> Unit = {}) {
        viewModelScope.launch {
            val code = CountryBorders.countryAt(coordinate, borders.await()) ?: return@launch
            val state = _state.value
            if (code == state.current?.cca3) return@launch
            val country = state.countries.firstOrNull { it.cca3 == code } ?: return@launch
            select(country)
            onSelected()
        }
    }

    /**
     * Outlines the selected country and asks the camera to fit it. Countries
     * without an outline fall back to a zoom based on their area. Unlike iOS
     * there's no place-search fallback after that; search only covers the
     * country list on Android.
     */
    private suspend fun updateRegion(country: Country) {
        val border = borders.await()[country.cca3]
        // A newer selection replaces this one; its job cancels this one too.
        if (_state.value.current?.cca3 != country.cca3) return
        val target = border?.focusRect?.let { CameraTarget.Outline(it) }
            ?: CameraTarget.Area(country.area, country.latlng)
        _state.update {
            it.copy(selectedBorder = border, cameraRequest = CameraRequest(++cameraRequestCount, target))
        }
    }
}
