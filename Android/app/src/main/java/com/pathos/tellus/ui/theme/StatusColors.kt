package com.pathos.tellus.ui.theme

import androidx.compose.ui.graphics.Color

/**
 * The gradient each travel status is drawn with, matching iOS `Array<Color>`
 * in Color.swift. The Tellus blues come from TravelStatusAssets.xcassets;
 * the rest are Apple's system colours.
 */
enum class StatusColors(val colors: List<Color>) {
    SECURE(listOf(TellusLight, SystemGreen, SystemGray)),
    SEMISECURE(listOf(TellusDark, SystemBlue, SystemGray)),
    CAUTION(listOf(SystemYellow, SystemOrange, SystemGray)),
    AVOID(listOf(SystemOrange, SystemRed.copy(alpha = 0.8f), SystemGray)),
    DANGER(listOf(SystemRed.copy(alpha = 0.8f), SystemRed, Color.Black.copy(alpha = 0.8f))),
}

private val TellusLight get() = Color(0xFF36BFFF)
private val TellusDark get() = Color(0xFF2400A3)
private val SystemGreen get() = Color(0xFF34C759)
private val SystemBlue get() = Color(0xFF007AFF)
private val SystemGray get() = Color(0xFF8E8E93)
private val SystemYellow get() = Color(0xFFFFCC00)
private val SystemOrange get() = Color(0xFFFF9500)
private val SystemRed get() = Color(0xFFFF3B30)
