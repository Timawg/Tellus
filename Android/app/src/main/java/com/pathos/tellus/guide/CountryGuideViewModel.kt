package com.pathos.tellus.guide

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.pathos.tellus.core.preferences.MapPreferencesStore
import com.pathos.tellus.countries.Country
import com.pathos.tellus.guide.democracy.DemocracyProfile
import com.pathos.tellus.guide.democracy.DemocracyProfiles
import com.pathos.tellus.guide.exchangerates.ExchangeRate
import com.pathos.tellus.guide.exchangerates.ExchangeRateService
import com.pathos.tellus.guide.profile.AnnualObservation
import com.pathos.tellus.guide.profile.CountryIndicatorObservation
import com.pathos.tellus.guide.profile.CountryProfileService
import com.pathos.tellus.guide.weather.DestinationWeather
import com.pathos.tellus.guide.weather.WeatherService
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import java.util.Currency
import java.util.Locale
import javax.inject.Inject

data class CountryGuideUiState(
    val destination: Country? = null,
    /** The user's nationality, which decides the home currency. */
    val passport: Country? = null,
    /** Weather at the destination's capital. */
    val weather: DestinationWeather? = null,
    /** What one unit of the home currency buys in each of the destination's currencies. Empty when they share one. */
    val exchangeRates: List<ExchangeRate> = emptyList(),
)

/**
 * The country guide's data for the selected destination, ported from iOS
 * `CountryGuideModel`. The map screen tells it which country is selected;
 * the passport comes from the saved nationality.
 */
@HiltViewModel
class CountryGuideViewModel @Inject constructor(
    private val weatherService: WeatherService,
    private val exchangeRateService: ExchangeRateService,
    private val profileService: CountryProfileService,
    private val democracyProfiles: DemocracyProfiles,
    private val preferences: MapPreferencesStore,
    private val json: Json,
    private val locale: Locale,
) : ViewModel() {

    private val _state = MutableStateFlow(CountryGuideUiState())
    val state: StateFlow<CountryGuideUiState> = _state.asStateFlow()

    private var destinationJob: Job? = null
    private var passportJob: Job? = null

    init {
        viewModelScope.launch {
            preferences.nationalityJson.collect { encoded ->
                val passport = encoded?.let {
                    try {
                        json.decodeFromString<Country>(it)
                    } catch (_: IllegalArgumentException) {
                        null
                    }
                }
                if (passport?.cca3 == _state.value.passport?.cca3) return@collect
                _state.update { it.copy(passport = passport) }
                refreshPassportInformation()
            }
        }
    }

    fun setDestination(country: Country?) {
        if (country?.cca3 == _state.value.destination?.cca3) return
        _state.update { it.copy(destination = country, weather = null) }
        destinationJob?.cancel()
        destinationJob = country?.let { destination ->
            viewModelScope.launch {
                val weather = loadOrNull { weatherService.getWeather(destination) }
                // Another country may have been chosen while loading; its job cancels this one too.
                if (_state.value.destination?.cca3 == destination.cca3) _state.update { it.copy(weather = weather) }
            }
        }
        refreshPassportInformation()
    }

    private fun refreshPassportInformation() {
        passportJob?.cancel()
        _state.update { it.copy(exchangeRates = emptyList()) }
        val selection = _state.value
        val destination = selection.destination ?: return
        passportJob = viewModelScope.launch {
            val home = homeCurrency(selection.passport)
            val destinationCurrencies = destination.currencies.orEmpty().keys.sorted().filter { it != home }
            if (destinationCurrencies.isEmpty()) return@launch
            val rates = loadOrNull { exchangeRateService.getRates(home) } ?: return@launch
            val current = _state.value
            if (current.destination?.cca3 != destination.cca3 || current.passport?.cca3 != selection.passport?.cca3) return@launch
            val exchangeRates = destinationCurrencies.mapNotNull { code ->
                rates.rates[code]?.let { ExchangeRate(home, code, it, rates.date) }
            }
            _state.update { it.copy(exchangeRates = exchangeRates) }
        }
    }

    /** The currency rates are shown from: the passport country's, else the device region's, else US dollars. */
    private fun homeCurrency(passport: Country?): String =
        passport?.currencies?.keys?.minOrNull()
            ?: try {
                Currency.getInstance(locale).currencyCode
            } catch (_: IllegalArgumentException) {
                null
            }
            ?: "USD"

    suspend fun loadCountryProfile(countryCode: String): List<CountryIndicatorObservation> =
        profileService.getProfile(countryCode)

    suspend fun loadHomicideTrend(countryCode: String): List<AnnualObservation> =
        profileService.getHomicideTrend(countryCode)

    suspend fun loadDemocracyProfile(countryCode: String?): DemocracyProfile =
        democracyProfiles.profile(countryCode)

    private suspend fun <T> loadOrNull(load: suspend () -> T): T? =
        try {
            load()
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            null
        }
}
