package com.pathos.tellus.guide

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.PrimaryScrollableTabRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.pathos.tellus.countries.Country
import com.pathos.tellus.countries.FlagImage
import com.pathos.tellus.guide.democracy.DemocracySafetyContent
import com.pathos.tellus.guide.exchangerates.ExchangeRate
import com.pathos.tellus.guide.profile.CountryProfileSections
import com.pathos.tellus.guide.weather.WeatherSection
import com.pathos.tellus.guide.weather.rememberWeatherFormat

/**
 * The country guide: a sheet with a tab per topic, ported from iOS
 * `DestinationGuideView`. Only Overview is filled in so far; the other tabs
 * arrive with their own issues.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CountryGuideSheet(
    country: Country,
    initialTopic: GuideTopic,
    state: CountryGuideUiState,
    neighbours: List<Country>,
    viewModel: CountryGuideViewModel,
    onSelectCountry: (Country) -> Unit,
    onDismiss: () -> Unit,
) {
    var topic by rememberSaveable { mutableStateOf(initialTopic) }
    var showsDemocracySafety by rememberSaveable { mutableStateOf(false) }
    BackHandler(enabled = showsDemocracySafety) { showsDemocracySafety = false }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
    ) {
        Column(Modifier.fillMaxSize()) {
            if (showsDemocracySafety) {
                DetailTopBar("Democracy & Safety", onBack = { showsDemocracySafety = false })
                Column(
                    Modifier
                        .verticalScroll(rememberScrollState())
                        .navigationBarsPadding(),
                ) {
                    DemocracySafetyContent(
                        cca3 = country.cca3,
                        cca2 = country.cca2,
                        loadDemocracy = viewModel::loadDemocracyProfile,
                        loadHomicides = viewModel::loadHomicideTrend,
                    )
                }
            } else {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(start = 24.dp, end = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        country.name?.common ?: "Destination",
                        modifier = Modifier.weight(1f),
                        style = MaterialTheme.typography.titleLarge,
                    )
                    TextButton(onClick = onDismiss) { Text("Done") }
                }
                PrimaryScrollableTabRow(selectedTabIndex = topic.ordinal, edgePadding = 16.dp) {
                    GuideTopic.entries.forEach { entry ->
                        Tab(selected = topic == entry, onClick = { topic = entry }, text = { Text(entry.title) })
                    }
                }
                when (topic) {
                    GuideTopic.OVERVIEW -> Overview(
                        country = country,
                        state = state,
                        neighbours = neighbours,
                        viewModel = viewModel,
                        onOpenDemocracySafety = { showsDemocracySafety = true },
                        onSelectNeighbour = {
                            onSelectCountry(it)
                            onDismiss()
                        },
                    )
                    else -> Box(Modifier.fillMaxSize().padding(32.dp), contentAlignment = Alignment.TopCenter) {
                        SecondaryText("${topic.title} isn’t available on Android yet.")
                    }
                }
            }
        }
    }
}

@Composable
private fun DetailTopBar(title: String, onBack: () -> Unit) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = onBack) {
            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
        }
        Text(title, style = MaterialTheme.typography.titleLarge)
    }
}

@Composable
private fun Overview(
    country: Country,
    state: CountryGuideUiState,
    neighbours: List<Country>,
    viewModel: CountryGuideViewModel,
    onOpenDemocracySafety: () -> Unit,
    onSelectNeighbour: (Country) -> Unit,
) {
    LazyColumn(contentPadding = PaddingValues(top = 8.dp, bottom = 32.dp)) {
        item {
            GuideSection(header = null) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable(role = Role.Button, onClick = onOpenDemocracySafety),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text("Democracy & Safety", Modifier.weight(1f))
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null)
                }
            }
        }
        item(key = "profile-${country.cca2}") {
            CountryProfileSections(country.cca2, viewModel::loadCountryProfile)
        }
        state.weather?.let { weather -> item { WeatherSection(weather) } }
        if (state.exchangeRates.isNotEmpty()) item { MoneySection(state.exchangeRates) }
        item { AtAGlanceSection(country) }
        if (neighbours.isNotEmpty()) item { NeighboursSection(neighbours, onSelectNeighbour) }
    }
}

@Composable
private fun MoneySection(rates: List<ExchangeRate>) {
    val locale = rememberWeatherFormat().locale
    GuideSection(
        header = "Exchange rate",
        footer = {
            Text(
                "From ${rates[0].home}, the currency of your passport or region. " +
                    "Daily rates from currency-api, updated ${rates[0].date}.",
            )
        },
    ) {
        rates.forEach { rate ->
            LabeledRow("1 ${rate.home}", "${ExchangeRate.format(rate.rate, locale)} ${rate.destination}")
            LabeledRow("1 ${rate.destination}", "${ExchangeRate.format(rate.inverse, locale)} ${rate.home}")
        }
    }
}

@Composable
private fun AtAGlanceSection(country: Country) {
    GuideSection("At a glance") {
        country.capital?.firstOrNull()?.let { LabeledRow("Capital", it) }
        (country.subregion ?: country.region)?.let { LabeledRow("Region", it) }
        val currencies = country.currencyDescriptions
        if (currencies.isNotEmpty()) {
            LabeledRow(if (currencies.size == 1) "Currency" else "Currencies", currencies.joinToString("\n"))
        }
        val languages = country.languageNames
        if (languages.isNotEmpty()) {
            LabeledRow(if (languages.size == 1) "Language" else "Languages", languages.joinToString(", "))
        }
        country.callingCode?.let { LabeledRow("Calling code", it) }
        country.tld?.firstOrNull()?.let { LabeledRow("Internet domain", it) }
        if (country.landlocked == true) LabeledRow("Coastline", "None, landlocked")
    }
}

@Composable
private fun NeighboursSection(neighbours: List<Country>, onSelect: (Country) -> Unit) {
    Column(Modifier.padding(vertical = 8.dp)) {
        Text(
            "Neighbours",
            modifier = Modifier.padding(start = 32.dp, bottom = 6.dp),
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        LazyRow(
            contentPadding = PaddingValues(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            items(neighbours, key = { it.cca3 ?: it.hashCode() }) { neighbour ->
                Surface(
                    shape = CircleShape,
                    color = MaterialTheme.colorScheme.surfaceContainerHigh,
                    modifier = Modifier.clickable(
                        role = Role.Button,
                        onClickLabel = "Show on the map",
                    ) { onSelect(neighbour) },
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        FlagImage(neighbour.flagUrl)
                        Text(neighbour.name?.common.orEmpty(), maxLines = 1)
                    }
                }
            }
        }
        Text(
            "Tap a country to go there.",
            modifier = Modifier.padding(start = 32.dp, top = 6.dp),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Start,
        )
    }
}
