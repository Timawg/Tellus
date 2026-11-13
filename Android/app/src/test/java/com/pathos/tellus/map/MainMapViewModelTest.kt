package com.pathos.tellus.map

import com.pathos.tellus.countries.CountriesService
import com.pathos.tellus.countries.Country
import com.pathos.tellus.countries.CountryBorder
import com.pathos.tellus.countries.CountryBorders
import com.pathos.tellus.countries.CountryBordersLoader
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.IOException
import kotlin.random.Random

@OptIn(ExperimentalCoroutinesApi::class)
class MainMapViewModelTest {

    @Before
    fun setUp() = Dispatchers.setMain(UnconfinedTestDispatcher())

    @After
    fun tearDown() = Dispatchers.resetMain()

    private fun country(name: String, code: String, area: Double? = null) =
        Country(name = Country.Name(common = name), cca3 = code, area = area, translations = emptyMap(), latlng = listOf(10.0, 20.0))

    private val sweden = country("Sweden", "SWE")
    private val norway = country("Norway", "NOR")
    private val tuvalu = country("Tuvalu", "TUV", area = 26.0)

    private fun box(west: Double, south: Double, east: Double, north: Double) =
        "[[$west,$south],[$east,$south],[$east,$north],[$west,$north],[$west,$south]]"

    private val borders = CountryBorders.parse(
        """{"features":[
          {"properties":{"cca3":"SWE"},"geometry":{"type":"Polygon","coordinates":[${box(11.0, 55.0, 24.0, 69.0)}]}},
          {"properties":{"cca3":"NOR"},"geometry":{"type":"Polygon","coordinates":[${box(5.0, 58.0, 10.9, 71.0)}]}}
        ]}""",
    )

    private class FakeCountries(var result: () -> List<Country>) : CountriesService {
        override suspend fun getAllCountries() = result()
    }

    private class FakeBorders(val loaded: CompletableDeferred<Map<String, CountryBorder>>) : CountryBordersLoader {
        var loads = 0
        override suspend fun load(): Map<String, CountryBorder> {
            loads++
            return loaded.await()
        }
    }

    /** Always picks the first country, so "random" selection is predictable. */
    private object FirstRandom : Random() {
        override fun nextBits(bitCount: Int) = 0
    }

    private fun viewModel(
        countries: FakeCountries = FakeCountries { listOf(sweden, tuvalu, norway) },
        loader: FakeBorders = FakeBorders(CompletableDeferred(borders)),
    ) = MainMapViewModel(countries, loader, FirstRandom)

    @Test
    fun loadsSortedCountriesAndSelectsOneWithItsOutline() = runTest {
        val state = viewModel().state.value

        assertEquals(listOf(norway, sweden, tuvalu), state.countries)
        assertEquals(norway, state.current)
        assertEquals("NOR", state.selectedBorder?.cca3)
        val target = state.cameraRequest?.target as CameraTarget.Outline
        assertEquals(borders.getValue("NOR").focusRect, target.rect)
    }

    @Test
    fun countryWithoutOutlineFallsBackToArea() = runTest {
        val viewModel = viewModel()
        viewModel.select(tuvalu)

        val state = viewModel.state.value
        assertNull(state.selectedBorder)
        assertEquals(CameraTarget.Area(26.0, listOf(10.0, 20.0)), state.cameraRequest?.target)
    }

    @Test
    fun failedLoadReportsErrorAndRetryRecovers() = runTest {
        val countries = FakeCountries { throw IOException("offline") }
        val viewModel = viewModel(countries)
        assertTrue(viewModel.state.value.loadFailed)
        assertNull(viewModel.state.value.current)

        countries.result = { listOf(sweden) }
        viewModel.retrieveCountries()

        assertFalse(viewModel.state.value.loadFailed)
        assertEquals(sweden, viewModel.state.value.current)
    }

    @Test
    fun tapSelectsCountryUnderIt() = runTest {
        val viewModel = viewModel()
        var ticks = 0

        viewModel.selectCountryAt(Coordinate(60.0, 15.0)) { ticks++ }

        assertEquals(sweden, viewModel.state.value.current)
        assertEquals("SWE", viewModel.state.value.selectedBorder?.cca3)
        assertEquals(1, ticks)
    }

    @Test
    fun tapOnSeaOrSelectedCountryDoesNothing() = runTest {
        val viewModel = viewModel()
        val before = viewModel.state.value
        var ticks = 0

        viewModel.selectCountryAt(Coordinate(0.0, -30.0)) { ticks++ }
        viewModel.selectCountryAt(Coordinate(65.0, 8.0)) { ticks++ }

        assertEquals(before, viewModel.state.value)
        assertEquals(0, ticks)
    }

    @Test
    fun olderSelectionDoesNotMoveCameraAfterNewerOne() = runTest {
        val loaded = CompletableDeferred<Map<String, CountryBorder>>()
        val loader = FakeBorders(loaded)
        val viewModel = viewModel(loader = loader)
        // Norway was selected on load and is waiting for the borders.
        viewModel.select(sweden)

        loaded.complete(borders)

        val state = viewModel.state.value
        assertEquals(sweden, state.current)
        assertEquals("SWE", state.selectedBorder?.cca3)
        assertEquals(1L, state.cameraRequest?.id)
        assertEquals(1, loader.loads)
    }
}
