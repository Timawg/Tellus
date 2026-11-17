package com.pathos.tellus.hazards

import androidx.compose.foundation.layout.size
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.pathos.tellus.R

/**
 * A hazard kind's symbol. Earthquakes use a drawn seismograph trace, like
 * iOS's `waveform.path.ecg`, since no emoji reads as an earthquake; the other
 * kinds use their emoji.
 */
@Composable
fun HazardSymbol(kind: DisasterAlert.Kind, modifier: Modifier = Modifier, size: Dp = 20.dp, tint: Color = LocalContentColor.current) {
    val icon = kind.iconRes
    if (icon != null) {
        Icon(painterResource(icon), contentDescription = null, modifier = modifier.size(size), tint = tint)
    } else {
        Text(kind.symbol, modifier)
    }
}

/** A drawn icon for kinds without a fitting emoji. */
val DisasterAlert.Kind.iconRes: Int?
    get() = if (this == DisasterAlert.Kind.EARTHQUAKE) R.drawable.ic_earthquake else null
