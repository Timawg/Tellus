package com.pathos.tellus.map

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import com.google.android.gms.maps.model.CameraPosition
import com.google.android.gms.maps.model.LatLng
import com.google.maps.android.compose.ComposeMapColorScheme
import com.google.maps.android.compose.GoogleMap
import com.google.maps.android.compose.MapUiSettings
import com.google.maps.android.compose.rememberCameraPositionState
import com.pathos.tellus.R

/** Full-screen world map. Layers and country selection are added on top of this. */
@Composable
fun MainMapScreen(modifier: Modifier = Modifier) {
    // Zoomed out to the whole world, like iOS's `MKCoordinateRegion(.world)`.
    val cameraPositionState = rememberCameraPositionState {
        position = CameraPosition.fromLatLngZoom(LatLng(20.0, 0.0), 1f)
    }
    val description = stringResource(R.string.map_description)
    GoogleMap(
        modifier = modifier
            .fillMaxSize()
            .semantics { contentDescription = description },
        cameraPositionState = cameraPositionState,
        mapColorScheme = if (isSystemInDarkTheme()) ComposeMapColorScheme.DARK else ComposeMapColorScheme.LIGHT,
        uiSettings = remember { MapUiSettings(zoomControlsEnabled = false, mapToolbarEnabled = false) },
    )
}
