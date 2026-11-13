package com.pathos.tellus.map

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
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
import com.pathos.tellus.countries.CountryBorder
import com.pathos.tellus.countries.CountrySelectionBar
import com.pathos.tellus.guide.CountryGuideSheet
import com.pathos.tellus.guide.CountryGuideViewModel
import com.pathos.tellus.guide.CountrySummaryCard
import com.pathos.tellus.guide.GuideTopic

/** The world map with country selection. Layers are added on top of this. */
@Composable
fun MainMapScreen(
    modifier: Modifier = Modifier,
    viewModel: MainMapViewModel = hiltViewModel(),
    guideViewModel: CountryGuideViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val guideState by guideViewModel.state.collectAsStateWithLifecycle()
    var isPickingCountry by rememberSaveable { mutableStateOf(false) }
    var guideTopic by rememberSaveable { mutableStateOf<GuideTopic?>(null) }
    LaunchedEffect(state.current) { guideViewModel.setDestination(state.current) }
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
            cameraPositionState.animateTo(fit, heightDp)
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
            onMapClick = { latLng ->
                viewModel.selectCountryAt(Coordinate(latLng.latitude, latLng.longitude)) {
                    haptics.performHapticFeedback(HapticFeedbackType.SegmentTick)
                }
            },
        ) {
            state.selectedBorder?.let { CountryOutline(it) }
        }

        state.current?.let { country ->
            CountrySummaryCard(
                country = country,
                weather = guideState.weather,
                exchangeRate = guideState.exchangeRates.firstOrNull(),
                onOpenGuide = { guideTopic = GuideTopic.OVERVIEW },
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
                FilledTonalIconButton(
                    onClick = viewModel::selectRandomCountry,
                    modifier = Modifier
                        .padding(horizontal = 16.dp)
                        .size(56.dp),
                ) {
                    Icon(
                        painter = painterResource(R.drawable.ic_globe),
                        contentDescription = stringResource(R.string.random_country),
                    )
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

private suspend fun CameraPositionState.animateTo(fit: MapFit, viewportHeightDp: Float) {
    val target = CameraPosition.fromLatLngZoom(
        LatLng(fit.center.latitude, fit.center.longitude),
        fit.zoom(viewportHeightDp),
    )
    animate(CameraUpdateFactory.newCameraPosition(target), durationMs = 1_000)
}
