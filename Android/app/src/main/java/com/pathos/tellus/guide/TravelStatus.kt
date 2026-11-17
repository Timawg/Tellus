package com.pathos.tellus.guide

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import android.text.format.DateFormat
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.pathos.tellus.countries.Country
import com.pathos.tellus.guide.advisories.AdvisoryStatus
import com.pathos.tellus.guide.outbreaks.OutbreakReport
import com.pathos.tellus.guide.passport.AdmissoryStatus
import com.pathos.tellus.hazards.DisasterAlert
import com.pathos.tellus.ui.theme.StatusColors
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/**
 * One of the things summed up by the dots on the map card's guide button and
 * shown in full in the guide, ported from iOS `TravelStatus`.
 */
data class TravelStatus(val kind: Kind, val colors: StatusColors, val title: String, val value: String) {

    enum class Kind(val topic: GuideTopic) {
        ADVISORY(GuideTopic.ENTRY),
        VISA(GuideTopic.ENTRY),
        HEALTH(GuideTopic.HEALTH),
        DISASTERS(GuideTopic.CLIMATE),
    }

    companion object {
        fun advisory(status: AdvisoryStatus?): TravelStatus? {
            val colors = status?.colors ?: return null
            return TravelStatus(Kind.ADVISORY, colors, "Travel advisory", status.data.eng.advisoryText)
        }

        fun visa(status: AdmissoryStatus?, passport: Country?): TravelStatus? {
            val colors = status?.colors ?: return null
            var value = capitalized(status.category)
            val days = status.duration.toIntOrNull()
            if (days != null && days > 0) value += " · up to $days days"
            val title = passport?.name?.common?.let { "Visa · $it passport" } ?: "Visa"
            return TravelStatus(Kind.VISA, colors, title, value)
        }

        /** How long a WHO report counts as a current outbreak, and how long as a recent one. */
        val CURRENT_OUTBREAK_AGE: Duration = Duration.ofDays(30)
        private val RECENT_OUTBREAK_AGE = Duration.ofDays(180)

        /**
         * From WHO's outbreak reports for the country: orange for one in the
         * last 30 days, blue for one in the last six months. [formatDay]
         * writes a report's date as day and abbreviated month.
         */
        fun health(reports: List<OutbreakReport>, now: Instant, formatDay: (Instant) -> String): TravelStatus {
            val title = "Disease outbreaks"
            val latest = reports.maxByOrNull { it.published }
                ?: return TravelStatus(Kind.HEALTH, StatusColors.SECURE, title, "No WHO outbreak reports")
            val age = Duration.between(latest.published, now)
            val reported = "${latest.disease}, reported ${formatDay(latest.published)}"
            return when {
                age <= CURRENT_OUTBREAK_AGE -> TravelStatus(Kind.HEALTH, StatusColors.CAUTION, title, reported)
                age <= RECENT_OUTBREAK_AGE -> TravelStatus(Kind.HEALTH, StatusColors.SEMISECURE, title, reported)
                else -> TravelStatus(Kind.HEALTH, StatusColors.SECURE, title, "No WHO reports in the last six months")
            }
        }

        /**
         * From GDACS alerts for the country: red or orange by the worst urgent
         * alert, blue when only a drought is listed.
         */
        fun disasters(alerts: List<DisasterAlert>): TravelStatus {
            val title = "Natural disasters"
            val urgent = alerts.filter { it.isUrgent }
            urgent.firstOrNull { it.level == DisasterAlert.Level.RED }?.let {
                return TravelStatus(Kind.DISASTERS, StatusColors.DANGER, title, "Red alert: ${it.name}")
            }
            urgent.firstOrNull()?.let {
                return TravelStatus(Kind.DISASTERS, StatusColors.CAUTION, title, "Orange alert: ${it.name}")
            }
            alerts.firstOrNull()?.let { return TravelStatus(Kind.DISASTERS, StatusColors.SEMISECURE, title, it.name) }
            return TravelStatus(Kind.DISASTERS, StatusColors.SECURE, title, "No active alerts")
        }

        /** Each word's first letter in upper case, like Foundation's `capitalized` ("visa-free" → "Visa-Free"). */
        private fun capitalized(text: String): String {
            val result = StringBuilder(text.length)
            var startOfWord = true
            for (char in text) {
                result.append(if (startOfWord) char.uppercaseChar() else char.lowercaseChar())
                startOfWord = !char.isLetterOrDigit()
            }
            return result.toString()
        }
    }
}

val AdvisoryStatus.colors: StatusColors?
    get() = when (data.state) {
        AdvisoryStatus.State.SECURE -> StatusColors.SECURE
        AdvisoryStatus.State.CAUTION -> StatusColors.SEMISECURE
        AdvisoryStatus.State.AVOID -> StatusColors.CAUTION
        AdvisoryStatus.State.DANGER -> StatusColors.DANGER
        null -> null
    }

val AdmissoryStatus.colors: StatusColors?
    get() = when (status) {
        AdmissoryStatus.Status.VISA_FREE -> StatusColors.SECURE
        AdmissoryStatus.Status.VISA_ON_ARRIVAL, AdmissoryStatus.Status.ELECTRONIC_VISA -> StatusColors.SEMISECURE
        AdmissoryStatus.Status.VISA_REQUIRED -> StatusColors.CAUTION
        AdmissoryStatus.Status.COVID_BAN, AdmissoryStatus.Status.NO_ADMISSION -> StatusColors.DANGER
        null -> null
    }

/** A report's date as day and abbreviated month in the user's locale ("13 Nov", "Nov 13"). */
@Composable
fun rememberDayFormatter(): (Instant) -> String {
    val locale = LocalConfiguration.current.locales[0]
    return remember(locale) {
        val formatter = DateTimeFormatter.ofPattern(DateFormat.getBestDateTimePattern(locale, "dMMM"), locale)
            .withZone(ZoneId.systemDefault())
        formatter::format
    }
}

/** A status's colour as a gradient dot, like iOS `CircularStatusView`. */
@Composable
fun StatusDot(colors: StatusColors, size: Dp, modifier: Modifier = Modifier) {
    Canvas(modifier.size(size)) {
        drawCircle(Brush.linearGradient(colors.colors, start = Offset.Zero, end = Offset(this.size.width, this.size.height)))
    }
}

/** A status as a row: its colour, what it's about and what it says. */
@Composable
fun TravelStatusRow(status: TravelStatus, modifier: Modifier = Modifier) {
    Row(modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        StatusDot(status.colors, 20.dp)
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(status.title, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(status.value)
        }
    }
}
