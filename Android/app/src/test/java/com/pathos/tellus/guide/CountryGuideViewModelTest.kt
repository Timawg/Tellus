package com.pathos.tellus.guide

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import com.pathos.tellus.core.preferences.MapPreferencesStore
import com.pathos.tellus.core.network.HttpError
import com.pathos.tellus.countries.Country
import com.pathos.tellus.guide.advisories.AdviceSection
import com.pathos.tellus.guide.advisories.AdvisoryService
import com.pathos.tellus.guide.advisories.AdvisoryStatus
import com.pathos.tellus.guide.democracy.DemocracyProfile
import com.pathos.tellus.guide.democracy.DemocracyProfiles
import com.pathos.tellus.guide.electricity.CountryElectricityProfile
import com.pathos.tellus.guide.electricity.ElectricityService
import com.pathos.tellus.guide.events.RecentEvents
import com.pathos.tellus.guide.events.RecentEventsService
import com.pathos.tellus.guide.exchangerates.ExchangeRate
import com.pathos.tellus.guide.exchangerates.ExchangeRateService
import com.pathos.tellus.guide.exchangerates.ExchangeRates
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
import com.pathos.tellus.guide.weather.WeatherCondition
import com.pathos.tellus.guide.weather.WeatherService
import com.pathos.tellus.ui.theme.StatusColors
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.first
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
import java.time.Instant
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

    /** Events and outages that wait until the test completes them, per country. */
    private class FakeEvents : RecentEventsService, InternetOutageService {
        val events = mutableMapOf<String, CompletableDeferred<RecentEvents?>>()
        override suspend fun getRecentEvents(country: Country) =
            events.getOrPut(country.cca3!!) { CompletableDeferred() }.await()
        override suspend fun getOutages(countryCode: String) = listOf(
            InternetOutage(Instant.EPOCH, Instant.EPOCH, isOngoing = true, signals = listOf("Routing (BGP)", countryCode)),
        )
    }

    private object NoPrices : PriceLevelService, ElectricityService {
        override suspend fun getPriceLevels(): EurostatPriceLevels = throw IOException("unused")
        override suspend fun getProfile(countryCode: String): CountryElectricityProfile? = null
    }

    /** Advisories answer with the given result per country code; visas are visa-free for 30 days. */
    private class FakeAdvisories : AdvisoryService, AdmissoryService {
        var advisory: (String) -> AdvisoryStatus = { throw HttpError.InvalidStatus(404, ByteArray(0)) }
        override suspend fun getAdvisoryStatus(destination: String) = advisory(destination)
        override suspend fun getAdmissoryStatus(passport: String, destination: String) =
            AdmissoryStatus.from(passport, destination, "30")
    }

    private fun advisory(state: Int) = AdvisoryStatus(
        AdvisoryStatus.Data(
            "SE", state,
            AdvisoryStatus.Information(
                "Sweden", "sweden", "Today", "Exercise normal security precautions",
                "<p>Normal.</p>", "<p>Bring a passport.</p>", "", "", "",
                "<h3>Local services</h3><p>Dial 112.</p>",
            ),
        ),
    )

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
        events: FakeEvents = FakeEvents(),
        advisories: FakeAdvisories = FakeAdvisories(),
    ) = CountryGuideViewModel(
        weather, rates, NoProfiles, advisories, advisories, events, events, NoPrices, NoPrices, NoProfiles,
        preferences, json, locale, dispatcher,
    )

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
    fun loadsEventsAndOutagesAndDropsOlderEvents() = runTest(dispatcher) {
        val events = FakeEvents()
        val viewModel = viewModel(events = events)
        viewModel.setDestination(sweden)
        assertEquals("SW", viewModel.state.value.internetOutages.single().signals.last())

        viewModel.setDestination(norway)
        events.events.getValue("SWE").complete(RecentEvents(emptyList(), "2026 in Sweden"))
        assertNull(viewModel.state.value.recentEvents)
        assertEquals("NO", viewModel.state.value.internetOutages.single().signals.last())

        events.events.getValue("NOR").complete(RecentEvents(emptyList(), "2026 in Norway"))
        assertEquals("2026 in Norway", viewModel.state.value.recentEvents?.articleTitle)
    }

    @Test
    fun missingAdvisoryIsNotAFailure() = runTest(dispatcher) {
        val viewModel = viewModel()
        viewModel.setDestination(sweden)
        val state = viewModel.state.value
        assertEquals(false, state.advisoryLoadFailed)
        assertEquals(false, state.isLoadingDestinationGuide)
        assertNull(state.destinationGuide)
    }

    @Test
    fun otherAdvisoryErrorsAreFailures() = runTest(dispatcher) {
        val advisories = FakeAdvisories().apply { advisory = { throw HttpError.InvalidStatus(500, ByteArray(0)) } }
        val viewModel = viewModel(advisories = advisories)
        viewModel.setDestination(sweden)
        assertEquals(true, viewModel.state.value.advisoryLoadFailed)
    }

    @Test
    fun advisoryIsParsedIntoGuideAndStatus() = runTest(dispatcher) {
        val advisories = FakeAdvisories().apply { advisory = { advisory(state = 0) } }
        val viewModel = viewModel(advisories = advisories)
        viewModel.setDestination(sweden)
        val state = viewModel.state.value

        assertEquals("tel:112", (state.destinationGuide!!.emergency.single() as AdviceSection.Block.Paragraph).text.links.single().url)
        assertEquals(listOf(TravelStatus.Kind.ADVISORY), state.travelStatuses.map { it.kind })
        assertEquals(StatusColors.SECURE, state.travelStatuses.single().colors)
    }

    @Test
    fun choosingPassportSavesItAndLoadsVisaRules() = runTest(dispatcher) {
        val preferences = preferences()
        val viewModel = viewModel(preferences = preferences)
        viewModel.setDestination(sweden)
        assertNull(viewModel.state.value.admissoryStatus)

        viewModel.setPassport(norway)
        advanceUntilIdle()

        assertEquals("NOR", viewModel.state.value.passport?.cca3)
        assertEquals("visa-free", viewModel.state.value.admissoryStatus?.category)
        assertEquals(TravelStatus.Kind.VISA, viewModel.state.value.travelStatuses.single().kind)
        assertEquals("NOR", json.decodeFromString<Country>(preferences.nationalityJson.first()!!).cca3)
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
