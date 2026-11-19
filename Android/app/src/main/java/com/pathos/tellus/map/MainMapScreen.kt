package com.pathos.tellus.map

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.LifecycleStartEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil3.compose.AsyncImage
import com.google.android.gms.maps.CameraUpdateFactory
import com.google.android.gms.maps.model.CameraPosition
import com.google.android.gms.maps.model.JointType
import com.google.android.gms.maps.model.LatLng
import com.google.maps.android.compose.CameraPositionState
import com.google.maps.android.compose.ComposeMapColorScheme
import com.google.maps.android.compose.GoogleMap
import com.google.maps.android.compose.MapUiSettings
import com.google.maps.android.compose.Polygon
import com.google.maps.android.compose.rememberCameraPositionState
import com.pathos.tellus.R
import com.pathos.tellus.cables.CableDetailsSheet
import com.pathos.tellus.cables.CableLayerViewModel
import com.pathos.tellus.cables.CablesLayer
import com.pathos.tellus.countries.Country
import com.pathos.tellus.countries.CountryBorder
import com.pathos.tellus.countries.CountrySelectionBar
import com.pathos.tellus.flights.FlightDetailsSheet
import com.pathos.tellus.flights.FlightsLayer
import com.pathos.tellus.flights.LiveFlightsUiState
import com.pathos.tellus.flights.LiveFlightsViewModel
import com.pathos.tellus.guide.CardAlert
import com.pathos.tellus.guide.CountryGuideSheet
import com.pathos.tellus.guide.CountryGuideViewModel
import com.pathos.tellus.guide.CountrySummaryCard
import com.pathos.tellus.guide.GuideTopic
import com.pathos.tellus.guide.passport.NationalityPicker
import com.pathos.tellus.guide.rememberDayFormatter
import com.pathos.tellus.guide.weather.rememberMinuteTicker
import com.pathos.tellus.hazards.HazardDetailsSheet
import com.pathos.tellus.hazards.HazardLayerViewModel
import com.pathos.tellus.hazards.HazardsLayer
import java.text.NumberFormat
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import kotlin.math.pow

/** The world map with country selection. Layers are added on top of this. */
@Composable
fun MainMapScreen(
    modifier: Modifier = Modifier,
    viewModel: MainMapViewModel = hiltViewModel(),
    guideViewModel: CountryGuideViewModel = hiltViewModel(),
    flightsViewModel: LiveFlightsViewModel = hiltViewModel(),
    hazardsViewModel: HazardLayerViewModel = hiltViewModel(),
    cablesViewModel: CableLayerViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val guideState by guideViewModel.state.collectAsStateWithLifecycle()
    val flightsState by flightsViewModel.state.collectAsStateWithLifecycle()
    val hazardsState by hazardsViewModel.state.collectAsStateWithLifecycle()
    val cablesState by cablesViewModel.state.collectAsStateWithLifecycle()
    // Flights and hazards refresh only while the map is on screen.
    LifecycleStartEffect(flightsViewModel, hazardsViewModel) {
        flightsViewModel.setMapActive(true)
        hazardsViewModel.setMapActive(true)
        onStopOrDispose {
            flightsViewModel.setMapActive(false)
            hazardsViewModel.setMapActive(false)
        }
    }
    var isPickingCountry by rememberSaveable { mutableStateOf(false) }
    var guideTopic by rememberSaveable { mutableStateOf<GuideTopic?>(null) }
    var isPickingPassport by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(state.current) { guideViewModel.setDestination(state.current, state.countries) }
    val now = rememberMinuteTicker()
    val formatDay = rememberDayFormatter()
    val haptics = LocalHapticFeedback.current
    // Zoomed out to the whole world, like iOS's `MKCoordinateRegion(.world)`.
    val cameraPositionState = rememberCameraPositionState {
        position = CameraPosition.fromLatLngZoom(LatLng(20.0, 0.0), 1f)
    }
    val mapDescription = stringResource(R.string.map_description)

    BoxWithConstraints(modifier.fillMaxSize()) {
        val aspectRatio = (maxWidth / maxHeight).toDouble()
        val heightDp = maxHeight.value
        // A camera move before the map has loaded is dropped, which lost the
        // first country's zoom at a cold start, so wait for the map.
        var isMapLoaded by remember { mutableStateOf(false) }
        LaunchedEffect(state.cameraRequest, isMapLoaded) {
            if (!isMapLoaded) return@LaunchedEffect
            val fit = state.cameraRequest?.target?.fit(aspectRatio) ?: return@LaunchedEffect
            cameraPositionState.moveTo(fit, heightDp)
        }
        // A moving camera pauses flight polling; once it settles, the new view is polled.
        LaunchedEffect(cameraPositionState.isMoving, isMapLoaded) {
            if (!isMapLoaded) return@LaunchedEffect
            if (cameraPositionState.isMoving) {
                flightsViewModel.viewportWillChange()
            } else {
                cameraPositionState.projection?.visibleRegion?.latLngBounds?.let { bounds ->
                    flightsViewModel.updateViewport(mercatorRect(bounds.southwest, bounds.northeast))
                }
            }
        }

        GoogleMap(
            modifier = Modifier
                .fillMaxSize()
                .semantics { contentDescription = mapDescription },
            cameraPositionState = cameraPositionState,
            mapColorScheme = if (isSystemInDarkTheme()) ComposeMapColorScheme.DARK else ComposeMapColorScheme.LIGHT,
            uiSettings = remember { MapUiSettings(zoomControlsEnabled = false, mapToolbarEnabled = false) },
            onMapLoaded = { isMapLoaded = true },
            // Marker taps don't reach here, so they never change the country.
            // A tap near a cable selects it instead, as on iOS.
            onMapClick = { latLng ->
                val coordinate = Coordinate(latLng.latitude, latLng.longitude)
                val zoom = cameraPositionState.position.zoom
                if (!cablesViewModel.tap(MercatorPoint.of(coordinate), tapTolerance(22, zoom), tapTolerance(12, zoom))) {
                    viewModel.selectCountryAt(coordinate) {
                        haptics.performHapticFeedback(HapticFeedbackType.SegmentTick)
                    }
                }
            },
        ) {
            state.selectedBorder?.let { CountryOutline(it) }
            cablesState.dataset?.let { dataset ->
                CablesLayer(dataset, cablesState.selected, cablesState.selectedLandingPoint)
            }
            if (hazardsState.isEnabled) {
                HazardsLayer(hazardsState.hazards, hazardsState.tracks, onSelect = hazardsViewModel::select)
            }
            if (flightsState.showsFlights) {
                FlightsLayer(
                    markers = flightsState.markers,
                    selectedId = flightsState.selection?.id,
                    route = flightsState.selectedRoute.takeIf { flightsState.selection != null },
                    flights = flightsState.flights,
                    onSelect = flightsViewModel::select,
                )
            }
        }

        state.current?.let { country ->
            CountrySummaryCard(
                country = country,
                weather = guideState.weather,
                exchangeRate = guideState.exchangeRates.firstOrNull(),
                onOpenGuide = { guideTopic = it },
                alert = CardAlert.from(guideState, now),
                statuses = guideState.travelStatuses(now, formatDay),
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .statusBarsPadding(),
            )
        }

        // Dims the map while the country list is open; tapping it closes the list.
        AnimatedVisibility(visible = isPickingCountry, enter = fadeIn(), exit = fadeOut()) {
            val closeLabel = stringResource(R.string.close_country_list)
            Box(
                Modifier
                    .fillMaxSize()
                    .background(Color.Black.copy(alpha = 0.35f))
                    .semantics {
                        contentDescription = closeLabel
                        role = Role.Button
                    }
                    .clickable { isPickingCountry = false },
            )
        }

        Column(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .navigationBarsPadding()
                .imePadding(),
        ) {
            AnimatedVisibility(visible = !isPickingCountry, enter = fadeIn(), exit = fadeOut()) {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                    verticalAlignment = Alignment.Bottom,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    FilledTonalIconButton(onClick = viewModel::selectRandomCountry, modifier = Modifier.size(56.dp)) {
                        Icon(
                            painter = painterResource(R.drawable.ic_globe),
                            contentDescription = stringResource(R.string.random_country),
                        )
                    }
                    Box(Modifier.weight(1f), contentAlignment = Alignment.BottomCenter) {
                        FlightsNotice(flightsState)
                    }
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        LayersButton(
                            showsFlights = flightsState.showsFlights,
                            onShowsFlightsChange = flightsViewModel::setShowsFlights,
                            showsHazards = hazardsState.isEnabled,
                            onShowsHazardsChange = hazardsViewModel::setEnabled,
                            showsCables = cablesState.isEnabled,
                            onShowsCablesChange = cablesViewModel::setEnabled,
                        )
                        PassportButton(passport = guideState.passport, onClick = { isPickingPassport = true })
                    }
                }
            }
            CountrySelectionBar(
                countries = state.countries,
                selected = state.current,
                isExpanded = isPickingCountry,
                onExpandedChange = { isPickingCountry = it },
                onSelect = {
                    viewModel.select(it)
                    isPickingCountry = false
                },
            )
        }
    }

    val guideCountry = state.current
    val topic = guideTopic
    if (guideCountry != null && topic != null) {
        CountryGuideSheet(
            country = guideCountry,
            initialTopic = topic,
            state = guideState,
            neighbours = viewModel.neighbours(guideCountry),
            viewModel = guideViewModel,
            onSelectCountry = viewModel::select,
            onDismiss = { guideTopic = null },
        )
    }

    hazardsState.selected?.let { hazard ->
        HazardDetailsSheet(hazard, onDismiss = { hazardsViewModel.select(null) })
    }

    cablesState.selected?.let { cable ->
        CableDetailsSheet(
            cable = cable,
            details = cablesState.selectedDetails,
            detailsFailed = cablesState.detailsFailed,
            onRetry = cablesViewModel::retryDetails,
            onDismiss = { cablesViewModel.select(null) },
        )
    }

    flightsState.selection?.let { selection ->
        FlightDetailsSheet(
            flightId = selection.id,
            state = flightsState,
            onDismiss = { flightsViewModel.select(null) },
        )
    }

    if (isPickingPassport) {
        NationalityPicker(
            countries = state.countries,
            selection = guideState.passport,
            onSelect = guideViewModel::setPassport,
            onDismiss = { isPickingPassport = false },
        )
    }

    if (state.loadFailed) {
        AlertDialog(
            onDismissRequest = viewModel::dismissLoadError,
            title = { Text(stringResource(R.string.countries_load_failed_title)) },
            text = { Text(stringResource(R.string.countries_load_failed_message)) },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.dismissLoadError()
                    viewModel.retrieveCountries()
                }) { Text(stringResource(R.string.retry)) }
            },
            dismissButton = {
                TextButton(onClick = viewModel::dismissLoadError) { Text(stringResource(R.string.ok)) }
            },
        )
    }
}

/** Switches map layers on and off, like iOS's layers menu. */
@Composable
private fun LayersButton(
    showsFlights: Boolean,
    onShowsFlightsChange: (Boolean) -> Unit,
    showsHazards: Boolean,
    onShowsHazardsChange: (Boolean) -> Unit,
    showsCables: Boolean,
    onShowsCablesChange: (Boolean) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        FilledTonalIconButton(onClick = { expanded = true }, modifier = Modifier.size(56.dp)) {
            Icon(painterResource(R.drawable.ic_layers), contentDescription = stringResource(R.string.map_layers))
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            LayerItem(stringResource(R.string.live_flights), "✈️", showsFlights, onShowsFlightsChange)
            LayerItem(stringResource(R.string.natural_hazards), "⚠️", showsHazards, onShowsHazardsChange)
            LayerItem(stringResource(R.string.undersea_cables), "🔌", showsCables, onShowsCablesChange)
        }
    }
}

@Composable
private fun LayerItem(title: String, symbol: String, isOn: Boolean, onChange: (Boolean) -> Unit) {
    DropdownMenuItem(
        text = { Text(title) },
        leadingIcon = { Text(symbol) },
        trailingIcon = { Checkbox(checked = isOn, onCheckedChange = null) },
        onClick = { onChange(!isOn) },
        modifier = Modifier.semantics { stateDescription = if (isOn) "On" else "Off" },
    )
}

/**
 * Explains why some or all aircraft are missing from the map: OpenSky is
 * rate limiting us, or there are more flights than are drawn at once.
 */
@Composable
private fun FlightsNotice(state: LiveFlightsUiState) {
    val pausedUntil = state.pausedUntil
    val text = when {
        !state.showsFlights -> null
        pausedUntil != null -> {
            // OpenSky's daily quota can pause us until the next day.
            val zone = ZoneId.systemDefault()
            val sameDay = pausedUntil.atZone(zone).toLocalDate() == LocalDate.now(zone)
            val format = if (sameDay) DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT) else DateTimeFormatter.ofPattern("EEEE HH:mm")
            "Live flights paused until ${format.withZone(zone).format(pausedUntil)}"
        }
        state.isShowingSubsetOfFlights -> {
            val number = NumberFormat.getIntegerInstance()
            "${number.format(state.markers.size)} of ${number.format(state.totalFlightCount)} flights\nZoom in for more"
        }
        else -> null
    } ?: return
    Surface(
        shape = RoundedCornerShape(18.dp),
        color = MaterialTheme.colorScheme.surfaceContainer.copy(alpha = 0.92f),
        tonalElevation = 3.dp,
        modifier = Modifier.semantics(mergeDescendants = true) {},
    ) {
        Text(
            "✈️ $text",
            modifier = Modifier.padding(horizontal = 14.dp, vertical = 8.dp),
            style = MaterialTheme.typography.bodySmall,
            textAlign = TextAlign.Center,
        )
    }
}

/**
 * A tap tolerance of [dp] in world widths. At zoom z the Maps SDK draws the
 * world 256 × 2^z dp wide. Cables use iOS's 22 points; landing points 12 dp,
 * a finger's reach around their 8 dp dot.
 */
internal fun tapTolerance(dp: Int, zoom: Float): Double = dp / (256 * 2.0.pow(zoom.toDouble()))

/** The Mercator rect a map's visible bounds cover, wrapping past the date line when needed. */
private fun mercatorRect(southwest: LatLng, northeast: LatLng): MercatorRect {
    val sw = MercatorPoint.of(Coordinate(southwest.latitude, southwest.longitude))
    val ne = MercatorPoint.of(Coordinate(northeast.latitude, northeast.longitude))
    val maxX = if (ne.x < sw.x) ne.x + 1 else ne.x
    return MercatorRect(sw.x, ne.y, maxX, sw.y)
}

/** Opens the passport picker, with the chosen passport's flag as a badge, like iOS's passport button. */
@Composable
private fun PassportButton(passport: Country?, onClick: () -> Unit) {
    val label = stringResource(R.string.your_passport)
    val value = passport?.name?.common ?: stringResource(R.string.not_set)
    FilledTonalIconButton(
        onClick = onClick,
        modifier = Modifier
            .size(56.dp)
            .semantics(mergeDescendants = true) {
                contentDescription = label
                stateDescription = value
            },
    ) {
        Box {
            Image(painterResource(R.drawable.passport_icon), contentDescription = null, modifier = Modifier.size(28.dp))
            passport?.flagUrl?.let { flag ->
                AsyncImage(
                    model = flag,
                    contentDescription = null,
                    modifier = Modifier
                        .align(Alignment.BottomEnd)
                        .offset(x = 6.dp, y = 4.dp)
                        .size(width = 18.dp, height = 12.dp)
                        .clip(RoundedCornerShape(2.dp)),
                )
            }
        }
    }
}

/**
 * The selected country's outline: a bright border with a faint fill. iOS
 * draws it white on its dark map; here it follows the theme so it stays
 * visible on the light map too.
 */
@Composable
private fun CountryOutline(border: CountryBorder) {
    val color = MaterialTheme.colorScheme.onSurface
    val strokeWidth = with(LocalDensity.current) { 2.dp.toPx() }
    val pieces = remember(border) {
        border.polygons.map { polygon ->
            polygon.outer.coordinates.map { LatLng(it.latitude, it.longitude) } to
                polygon.holes.map { hole -> hole.coordinates.map { LatLng(it.latitude, it.longitude) } }
        }
    }
    pieces.forEach { (outer, holes) ->
        Polygon(
            points = outer,
            holes = holes,
            strokeColor = color.copy(alpha = 0.9f),
            fillColor = color.copy(alpha = 0.08f),
            strokeWidth = strokeWidth,
            strokeJointType = JointType.ROUND,
        )
    }
}

private fun CameraPositionState.moveTo(fit: MapFit, viewportHeightDp: Float) {
    val target = CameraPosition.fromLatLngZoom(
        LatLng(fit.center.latitude, fit.center.longitude),
        fit.zoom(viewportHeightDp),
    )
    // Instant, like iOS's `setRegion(_:animated: false)`. An animation could
    // also be cancelled when the map is stopped and started at launch, which
    // left the first country unzoomed.
    move(CameraUpdateFactory.newCameraPosition(target))
}
