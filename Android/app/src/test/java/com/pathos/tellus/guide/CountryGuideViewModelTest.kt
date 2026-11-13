package com.pathos.tellus.guide

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import com.pathos.tellus.core.preferences.MapPreferencesStore
import com.pathos.tellus.countries.Country
import com.pathos.tellus.guide.democracy.DemocracyProfile
import com.pathos.tellus.guide.democracy.DemocracyProfiles
import com.pathos.tellus.guide.exchangerates.ExchangeRate
import com.pathos.tellus.guide.exchangerates.ExchangeRateService
import com.pathos.tellus.guide.exchangerates.ExchangeRates
import com.pathos.tellus.guide.profile.AnnualObservation
import com.pathos.tellus.guide.profile.CountryIndicatorObservation
import com.pathos.tellus.guide.profile.CountryProfileService
import com.pathos.tellus.guide.weather.DestinationWeather
import com.pathos.tellus.guide.weather.WeatherCondition
import com.pathos.tellus.guide.weather.WeatherService
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import kotlinx.serialization.json.Json
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.IOException
import java.time.ZoneOffset
import java.util.Locale

@OptIn(ExperimentalCoroutinesApi::class)
class CountryGuideViewModelTest {

    @get:Rule
    val folder = TemporaryFolder()

    private val dispatcher = UnconfinedTestDispatcher()

    @Before
    fun setUp() = Dispatchers.setMain(dispatcher)

    @After
    fun tearDown() = Dispatchers.resetMain()

    private val json = Json { ignoreUnknownKeys = true }

    private fun country(code: String, currency: String?) = Country(
        name = Country.Name(code), cca2 = code.take(2), cca3 = code,
        currencies = currency?.let { mapOf(it to Country.CurrencyInfo(name = it)) },
        translations = emptyMap(), latlng = listOf(0.0, 0.0),
    )

    private val sweden = country("SWE", "SEK")
    private val norway = country("NOR", "NOK")
    private val finland = country("FIN", "EUR")

    private fun weather(place: String) =
        DestinationWeather(place, ZoneOffset.UTC, WeatherCondition.CLEAR, true, 1.0, 1.0, 1.0, 50, emptyList())

    private class FakeWeather : WeatherService {
        val pending = mutableMapOf<String, CompletableDeferred<DestinationWeather>>()
        override suspend fun getWeather(country: Country) =
            pending.getOrPut(country.cca3!!) { CompletableDeferred() }.await()
    }

    private class FakeRates(var fail: Boolean = false) : ExchangeRateService {
        val bases = mutableListOf<String>()
        override suspend fun getRates(base: String): ExchangeRates {
            bases += base
            if (fail) throw IOException("offline")
            return ExchangeRates(base, "2026-11-13", mapOf("SEK" to 11.5, "NOK" to 11.7, "EUR" to 1.0))
        }
    }

    private object NoProfiles : CountryProfileService, DemocracyProfiles {
        override suspend fun getProfile(countryCode: String) = emptyList<CountryIndicatorObservation>()
        override suspend fun getHomicideTrend(countryCode: String) = emptyList<AnnualObservation>()
        override suspend fun profile(countryCode: String?) = DemocracyProfile(16, emptyList())
    }

    private fun TestScope.preferences(): MapPreferencesStore {
        val file = folder.newFile("prefs.preferences_pb").also { it.delete() }
        return MapPreferencesStore(PreferenceDataStoreFactory.create(scope = backgroundScope) { file })
    }

    private fun TestScope.viewModel(
        weather: FakeWeather = FakeWeather(),
        rates: FakeRates = FakeRates(),
        preferences: MapPreferencesStore = preferences(),
        locale: Locale = Locale.GERMANY,
    ) = CountryGuideViewModel(weather, rates, NoProfiles, NoProfiles, preferences, json, locale)

    @Test
    fun loadsWeatherForDestination() = runTest(dispatcher) {
        val weather = FakeWeather()
        val viewModel = viewModel(weather = weather)
        viewModel.setDestination(sweden)
        weather.pending.getValue("SWE").complete(weather("Stockholm"))

        assertEquals("Stockholm", viewModel.state.value.weather?.placeName)
    }

    @Test
    fun olderWeatherIsDroppedAfterSelectionChanges() = runTest(dispatcher) {
        val weather = FakeWeather()
        val viewModel = viewModel(weather = weather)
        viewModel.setDestination(sweden)
        viewModel.setDestination(norway)
        weather.pending.getValue("SWE").complete(weather("Stockholm"))
        assertNull(viewModel.state.value.weather)

        weather.pending.getValue("NOR").complete(weather("Oslo"))
        assertEquals("Oslo", viewModel.state.value.weather?.placeName)
    }

    @Test
    fun ratesUseDeviceRegionWithoutPassport() = runTest(dispatcher) {
        val rates = FakeRates()
        val viewModel = viewModel(rates = rates, locale = Locale.GERMANY)
        viewModel.setDestination(sweden)

        assertEquals(listOf("EUR"), rates.bases)
        assertEquals(listOf(ExchangeRate("EUR", "SEK", 11.5, "2026-11-13")), viewModel.state.value.exchangeRates)
    }

    @Test
    fun ratesUsePassportCurrency() = runTest(dispatcher) {
        val rates = FakeRates()
        val preferences = preferences()
        preferences.setNationalityJson(json.encodeToString(Country.serializer(), norway))
        val viewModel = viewModel(rates = rates, preferences = preferences)
        advanceUntilIdle()
        viewModel.setDestination(sweden)

        assertEquals("NOK", viewModel.state.value.exchangeRates.single().home)
    }

    @Test
    fun sharedCurrencyHasNoRates() = runTest(dispatcher) {
        val rates = FakeRates()
        val viewModel = viewModel(rates = rates, locale = Locale.GERMANY)
        viewModel.setDestination(finland)

        assertEquals(emptyList<ExchangeRate>(), viewModel.state.value.exchangeRates)
        assertEquals(emptyList<String>(), rates.bases)
    }

    @Test
    fun failedRatesLeaveNoRates() = runTest(dispatcher) {
        val viewModel = viewModel(rates = FakeRates(fail = true))
        viewModel.setDestination(sweden)
        assertEquals(emptyList<ExchangeRate>(), viewModel.state.value.exchangeRates)
    }
}
