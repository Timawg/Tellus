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
import androidx.compose.foundation.lazy.LazyListScope
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
import androidx.compose.material3.ModalBottomSheetProperties
import androidx.compose.material3.PrimaryScrollableTabRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.pathos.tellus.countries.Country
import com.pathos.tellus.countries.FlagImage
import com.pathos.tellus.guide.advisories.AdviceBlocks
import com.pathos.tellus.guide.advisories.GuideAdviceSource
import com.pathos.tellus.guide.advisories.TravelAdviceContent
import com.pathos.tellus.guide.democracy.DemocracySafetyContent
import com.pathos.tellus.guide.electricity.ElectricityContent
import com.pathos.tellus.guide.events.RecentEventsSection
import com.pathos.tellus.guide.exchangerates.ExchangeRate
import com.pathos.tellus.guide.outages.OutagesSection
import com.pathos.tellus.guide.outbreaks.OutbreaksSection
import com.pathos.tellus.guide.prices.CostOfLivingContent
import com.pathos.tellus.guide.profile.CountryProfileSections
import com.pathos.tellus.guide.weather.WeatherSection
import com.pathos.tellus.guide.weather.rememberMinuteTicker
import com.pathos.tellus.hazards.DisasterAlertsSection
import com.pathos.tellus.guide.weather.rememberWeatherFormat

/**
 * The country guide: a sheet with a tab per topic, ported from iOS
 * `DestinationGuideView`.
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
    var detail by rememberSaveable { mutableStateOf<GuideDetail?>(null) }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        // The sheet would close on Back before a detail page could handle it.
        properties = ModalBottomSheetProperties(shouldDismissOnBackPress = false),
    ) {
        BackHandler {
            if (detail != null) detail = null else onDismiss()
        }
        Column(Modifier.fillMaxSize()) {
            val shownDetail = detail
            if (shownDetail != null) {
                DetailTopBar(shownDetail.title, onBack = { detail = null })
                Column(
                    Modifier
                        .verticalScroll(rememberScrollState())
                        .navigationBarsPadding(),
                ) {
                    val name = country.name?.common.orEmpty()
                    when (shownDetail) {
                        GuideDetail.DEMOCRACY_SAFETY -> DemocracySafetyContent(
                            cca3 = country.cca3,
                            cca2 = country.cca2,
                            loadDemocracy = viewModel::loadDemocracyProfile,
                            loadHomicides = viewModel::loadHomicideTrend,
                        )
                        GuideDetail.COST_OF_LIVING -> CostOfLivingContent(
                            countryCode = country.cca2.orEmpty(),
                            countryName = name.ifEmpty { country.cca2.orEmpty() },
                            load = viewModel::loadPriceLevels,
                        )
                        GuideDetail.ELECTRICITY -> ElectricityContent(
                            countryCode = country.cca3.orEmpty(),
                            countryName = name.ifEmpty { country.cca3.orEmpty() },
                            load = viewModel::loadElectricityProfile,
                        )
                    }
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
                        onOpenDetail = { detail = it },
                        onOpenTopic = { topic = it },
                        onSelectNeighbour = {
                            onSelectCountry(it)
                            onDismiss()
                        },
                    )
                    GuideTopic.ENTRY -> Entry(state)
                    GuideTopic.HEALTH -> Health(state)
                    GuideTopic.LAWS -> Laws(state)
                    GuideTopic.CLIMATE -> Climate(state)
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
    onOpenDetail: (GuideDetail) -> Unit,
    onOpenTopic: (GuideTopic) -> Unit,
    onSelectNeighbour: (Country) -> Unit,
) {
    val now = rememberMinuteTicker()
    val formatDay = rememberDayFormatter()
    LazyColumn(contentPadding = PaddingValues(top = 8.dp, bottom = 32.dp)) {
        val statuses = state.travelStatuses(now, formatDay)
        if (statuses.isNotEmpty()) item { StatusOverviewSection(statuses, onOpenTopic) }
        item { GuideSection(header = null) { DetailRow(GuideDetail.DEMOCRACY_SAFETY, onOpenDetail) } }
        item(key = "profile-${country.cca2}") {
            CountryProfileSections(country.cca2, viewModel::loadCountryProfile)
        }
        if (country.cca2 != null) {
            item { GuideSection("Prices") { DetailRow(GuideDetail.COST_OF_LIVING, onOpenDetail) } }
        }
        if (country.cca3 != null) {
            item { GuideSection("Energy") { DetailRow(GuideDetail.ELECTRICITY, onOpenDetail) } }
        }
        state.recentEvents?.takeIf { it.events.isNotEmpty() }?.let { events -> item { RecentEventsSection(events) } }
        if (state.internetOutages.isNotEmpty()) item { OutagesSection(state.internetOutages) }
        state.weather?.let { weather -> item { WeatherSection(weather) } }
        if (state.exchangeRates.isNotEmpty()) item { MoneySection(state.exchangeRates) }
        item { AtAGlanceSection(country) }
        item { EmergencySection(state) }
        if (neighbours.isNotEmpty()) item { NeighboursSection(neighbours, onSelectNeighbour) }
    }
}

/** The topic's travel advice and where it comes from, shared by the advice tabs. */
private fun LazyListScope.travelAdvice(topic: GuideTopic, state: CountryGuideUiState) {
    item {
        Column {
            TravelAdviceContent(
                topic = topic,
                guide = state.destinationGuide,
                advisoryStatus = state.advisoryStatus,
                isLoading = state.isLoadingDestinationGuide,
                loadFailed = state.advisoryLoadFailed,
            )
        }
    }
    state.destinationGuide?.let { guide -> item { GuideAdviceSource(guide) } }
}

/** The Climate tab: the disaster status, GDACS alerts, then disaster and climate advice. */
@Composable
private fun Climate(state: CountryGuideUiState) {
    val now = rememberMinuteTicker()
    val formatDay = rememberDayFormatter()
    LazyColumn(contentPadding = PaddingValues(top = 8.dp, bottom = 32.dp)) {
        item {
            val disasters = state.travelStatuses(now, formatDay).filter { it.kind == TravelStatus.Kind.DISASTERS }
            GuideSection("Status") { disasters.forEach { TravelStatusRow(it) } }
        }
        if (state.disasterAlerts.isNotEmpty()) item { DisasterAlertsSection(state.disasterAlerts) }
        travelAdvice(GuideTopic.CLIMATE, state)
    }
}

/** The Laws tab: only the laws and culture advice, as on iOS. */
@Composable
private fun Laws(state: CountryGuideUiState) {
    LazyColumn(contentPadding = PaddingValues(top = 8.dp, bottom = 32.dp)) {
        travelAdvice(GuideTopic.LAWS, state)
    }
}

/** The Health tab: the outbreak status, WHO's reports, then health advice. */
@Composable
private fun Health(state: CountryGuideUiState) {
    val now = rememberMinuteTicker()
    val formatDay = rememberDayFormatter()
    LazyColumn(contentPadding = PaddingValues(top = 8.dp, bottom = 32.dp)) {
        item {
            val health = state.travelStatuses(now, formatDay).filter { it.kind == TravelStatus.Kind.HEALTH }
            GuideSection("Status") { health.forEach { TravelStatusRow(it) } }
        }
        if (state.outbreakReports.isNotEmpty()) item { OutbreaksSection(state.outbreakReports) }
        travelAdvice(GuideTopic.HEALTH, state)
    }
}

/** The Entry tab: visa status for the passport, then the advisory and entry advice. */
@Composable
private fun Entry(state: CountryGuideUiState) {
    val now = rememberMinuteTicker()
    val formatDay = rememberDayFormatter()
    LazyColumn(contentPadding = PaddingValues(top = 8.dp, bottom = 32.dp)) {
        item {
            val visa = state.travelStatuses(now, formatDay).filter { it.kind == TravelStatus.Kind.VISA }
            GuideSection(
                header = "Status",
                footer = if (state.admissoryStatus == null) {
                    { Text("Choose your passport on the map to see visa rules.") }
                } else null,
            ) {
                if (visa.isEmpty()) SecondaryText("No visa information") else visa.forEach { TravelStatusRow(it) }
            }
        }
        travelAdvice(GuideTopic.ENTRY, state)
    }
}

/** Every status, each opening the tab that explains it. These are the dots on the map card's guide button. */
@Composable
private fun StatusOverviewSection(statuses: List<TravelStatus>, onOpenTopic: (GuideTopic) -> Unit) {
    GuideSection("Status") {
        statuses.forEach { status ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(role = Role.Button, onClickLabel = "Show ${status.kind.topic.title}") {
                        onOpenTopic(status.kind.topic)
                    },
                verticalAlignment = Alignment.CenterVertically,
            ) {
                TravelStatusRow(status, Modifier.weight(1f))
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null)
            }
        }
    }
}

/** Emergency numbers from the advisory's "Local services", with short numbers tappable. */
@Composable
private fun EmergencySection(state: CountryGuideUiState) {
    val emergency = state.destinationGuide?.emergency.orEmpty()
    when {
        emergency.isNotEmpty() -> GuideSection(
            header = "Emergency numbers",
            // Some places have no central number, only advice.
            footer = if (emergency.any { it.hasPhoneLink }) {
                { Text("Tap a number to call it.") }
            } else null,
        ) { AdviceBlocks(emergency) }
        state.isLoadingDestinationGuide -> GuideSection("Emergency numbers") { LoadingRow("Loading advice…") }
    }
}

/** Pages the Overview links to, shown in place of the tabs. */
enum class GuideDetail(val title: String) {
    DEMOCRACY_SAFETY("Democracy & Safety"),
    COST_OF_LIVING("Cost of living"),
    ELECTRICITY("Electricity profile"),
}

@Composable
private fun DetailRow(detail: GuideDetail, onOpen: (GuideDetail) -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(role = Role.Button) { onOpen(detail) },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(detail.title, Modifier.weight(1f))
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null)
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
