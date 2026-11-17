package com.pathos.tellus.guide

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.pathos.tellus.core.coroutines.DefaultDispatcher
import com.pathos.tellus.core.network.HttpError
import com.pathos.tellus.core.preferences.MapPreferencesStore
import com.pathos.tellus.countries.Country
import com.pathos.tellus.guide.advisories.AdvisoryService
import com.pathos.tellus.guide.advisories.AdvisoryStatus
import com.pathos.tellus.guide.advisories.DestinationGuide
import com.pathos.tellus.guide.democracy.DemocracyProfile
import com.pathos.tellus.guide.democracy.DemocracyProfiles
import com.pathos.tellus.guide.electricity.CountryElectricityProfile
import com.pathos.tellus.guide.electricity.ElectricityService
import com.pathos.tellus.guide.events.RecentEvents
import com.pathos.tellus.guide.events.RecentEventsService
import com.pathos.tellus.guide.exchangerates.ExchangeRate
import com.pathos.tellus.guide.exchangerates.ExchangeRateService
import com.pathos.tellus.guide.outages.InternetOutage
import com.pathos.tellus.guide.outages.InternetOutageService
import com.pathos.tellus.guide.passport.AdmissoryService
import com.pathos.tellus.guide.passport.AdmissoryStatus
import com.pathos.tellus.guide.prices.EurostatPriceLevels
import com.pathos.tellus.guide.prices.PriceLevelService
import com.pathos.tellus.guide.profile.AnnualObservation
import com.pathos.tellus.guide.profile.CountryIndicatorObservation
import com.pathos.tellus.guide.profile.CountryProfileService
import com.pathos.tellus.guide.weather.DestinationWeather
import com.pathos.tellus.guide.weather.WeatherService
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
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
    /** Dated events from Wikipedia's "<year> in <country>" article. */
    val recentEvents: RecentEvents? = null,
    /** Internet outages in the destination over the last week, seen by at least two independent signals. */
    val internetOutages: List<InternetOutage> = emptyList(),
    /** The Canadian travel advisory for the destination. */
    val advisoryStatus: AdvisoryStatus? = null,
    /** The advisory failed for a reason other than there being none (404). */
    val advisoryLoadFailed: Boolean = false,
    /** The advisory's advice and emergency numbers, parsed for the guide's tabs. */
    val destinationGuide: DestinationGuide? = null,
    val isLoadingDestinationGuide: Boolean = false,
    /** Visa rules for the passport at the destination. */
    val admissoryStatus: AdmissoryStatus? = null,
) {
    /** Advisory and visa statuses, in the order the card's dots show them. */
    val travelStatuses: List<TravelStatus>
        get() = listOfNotNull(TravelStatus.advisory(advisoryStatus), TravelStatus.visa(admissoryStatus, passport))
}

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
    private val advisoryService: AdvisoryService,
    private val admissoryService: AdmissoryService,
    private val recentEventsService: RecentEventsService,
    private val outageService: InternetOutageService,
    private val priceLevelService: PriceLevelService,
    private val electricityService: ElectricityService,
    private val democracyProfiles: DemocracyProfiles,
    private val preferences: MapPreferencesStore,
    private val json: Json,
    private val locale: Locale,
    @param:DefaultDispatcher private val parseDispatcher: CoroutineDispatcher,
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
        _state.update {
            it.copy(
                destination = country,
                weather = null,
                recentEvents = null,
                internetOutages = emptyList(),
                advisoryStatus = null,
                advisoryLoadFailed = false,
                destinationGuide = null,
                isLoadingDestinationGuide = country?.cca2 != null,
            )
        }
        destinationJob?.cancel()
        destinationJob = country?.let { destination ->
            viewModelScope.launch {
                launch {
                    val weather = loadOrNull { weatherService.getWeather(destination) }
                    updateDestination(destination) { it.copy(weather = weather) }
                }
                launch {
                    val events = loadOrNull { recentEventsService.getRecentEvents(destination) }
                    updateDestination(destination) { it.copy(recentEvents = events) }
                }
                launch { updateAdvisory(destination) }
                launch {
                    val code = destination.cca2 ?: return@launch
                    val outages = loadOrNull { outageService.getOutages(code) }.orEmpty()
                    updateDestination(destination) { it.copy(internetOutages = outages) }
                }
            }
        }
        refreshPassportInformation()
    }

    private suspend fun updateAdvisory(destination: Country) {
        val code = destination.cca2 ?: return
        val status = try {
            advisoryService.getAdvisoryStatus(code)
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            // A 404 means Canada publishes no advisory for this place, which isn't a failure.
            val failed = !(error is HttpError.InvalidStatus && error.code == 404)
            updateDestination(destination) { it.copy(advisoryLoadFailed = failed, isLoadingDestinationGuide = false) }
            return
        }
        updateDestination(destination) { it.copy(advisoryStatus = status) }
        val guide = withContext(parseDispatcher) { DestinationGuide.from(status.data.eng) }
        // Another country may have been chosen while parsing.
        updateDestination(destination) { it.copy(destinationGuide = guide, isLoadingDestinationGuide = false) }
    }

    /** Saves the passport the user travels on, which drives visa rules and the home currency. */
    fun setPassport(country: Country?) {
        viewModelScope.launch {
            preferences.setNationalityJson(country?.let { json.encodeToString(Country.serializer(), it) })
        }
    }

    /** Applies a loaded result only if [destination] is still selected; a newer selection cancels this one too. */
    private fun updateDestination(destination: Country, change: (CountryGuideUiState) -> CountryGuideUiState) {
        if (_state.value.destination?.cca3 == destination.cca3) _state.update(change)
    }

    private fun refreshPassportInformation() {
        passportJob?.cancel()
        _state.update { it.copy(exchangeRates = emptyList(), admissoryStatus = null) }
        val selection = _state.value
        val destination = selection.destination ?: return
        passportJob = viewModelScope.launch {
            launch {
                val passport = selection.passport?.cca2 ?: return@launch
                val code = destination.cca2 ?: return@launch
                val status = loadOrNull { admissoryService.getAdmissoryStatus(passport, code) }
                val current = _state.value
                if (current.destination?.cca3 == destination.cca3 && current.passport?.cca3 == selection.passport.cca3) {
                    _state.update { it.copy(admissoryStatus = status) }
                }
            }
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

    suspend fun loadPriceLevels(): EurostatPriceLevels = priceLevelService.getPriceLevels()

    suspend fun loadElectricityProfile(countryCode: String): CountryElectricityProfile? =
        electricityService.getProfile(countryCode)

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
