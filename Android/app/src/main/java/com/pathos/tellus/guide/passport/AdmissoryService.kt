package com.pathos.tellus.guide.passport

import com.pathos.tellus.core.network.NetworkService
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import okhttp3.Request
import java.io.IOException
import javax.inject.Inject
import javax.inject.Singleton

/** Visa requirements for one passport at one destination, ported from iOS `AdmissoryStatus`. */
data class AdmissoryStatus(
    val passport: String,
    val destination: String,
    /** Visa-free days allowed, or empty when the dataset doesn't give a number. */
    val duration: String,
    /** "visa-free", "e-visa", "visa on arrival", "visa required", "not admitted", or the raw value. */
    val category: String,
) {
    enum class Status { VISA_FREE, ELECTRONIC_VISA, VISA_ON_ARRIVAL, VISA_REQUIRED, COVID_BAN, NO_ADMISSION }

    val status: Status?
        get() = when (category.lowercase()) {
            "eta", "evisa", "e-visa", "visa on arrival / evisa" -> Status.ELECTRONIC_VISA
            "visa-free" -> Status.VISA_FREE
            "visa on arrival" -> Status.VISA_ON_ARRIVAL
            "visa required" -> Status.VISA_REQUIRED
            "covid ban" -> Status.COVID_BAN
            "not admitted" -> Status.NO_ADMISSION
            else -> null
        }

    companion object {
        /**
         * Builds a status from a raw Passport Index requirement, e.g. "90",
         * "visa required", "visa on arrival", "e-visa" or "no admission".
         */
        fun from(passport: String, destination: String, requirement: String): AdmissoryStatus {
            val trimmed = requirement.trim()
            // A numeric requirement is the number of visa-free days allowed.
            val duration = if (trimmed.toIntOrNull() != null) trimmed else ""
            return AdmissoryStatus(passport, destination, duration, normalizeCategory(trimmed))
        }

        private fun normalizeCategory(requirement: String): String {
            val value = requirement.lowercase().trim()
            // Numbers (and "-1" for one's own country) mean visa-free entry.
            if (value.toIntOrNull() != null) return "visa-free"
            return when (value) {
                "visa free", "-1" -> "visa-free"
                "visa on arrival" -> "visa on arrival"
                "e-visa", "eta" -> "e-visa"
                "visa required" -> "visa required"
                "no admission" -> "not admitted"
                else -> value
            }
        }

        /** Parses the tidy CSV ("Passport,Destination,Requirement") into a map keyed "PASSPORT>DESTINATION". */
        fun parse(csv: String): Map<String, String> =
            csv.lineSequence().drop(1).mapNotNull { line ->
                val columns = line.split(',', limit = 3)
                if (columns.size != 3) return@mapNotNull null
                "${columns[0].trim()}>${columns[1].trim()}" to columns[2].trim()
            }.toMap()
    }
}

interface AdmissoryService {
    suspend fun getAdmissoryStatus(passport: String, destination: String): AdmissoryStatus
}

/**
 * Visa requirements from the open Passport Index dataset, served over
 * jsDelivr. It's one CSV covering every passport and destination, fetched once
 * per session and kept in memory, as on iOS.
 */
@Singleton
class PassportIndexAdmissoryService @Inject constructor(
    private val networkService: NetworkService,
) : AdmissoryService {

    private val mutex = Mutex()
    private var requirements: Map<String, String>? = null

    override suspend fun getAdmissoryStatus(passport: String, destination: String): AdmissoryStatus {
        val requirement = loadRequirements()["$passport>$destination"]
            ?: throw IOException("No requirement for $passport>$destination")
        return AdmissoryStatus.from(passport, destination, requirement)
    }

    // Held across the download so concurrent lookups share one request.
    private suspend fun loadRequirements(): Map<String, String> = mutex.withLock {
        requirements ?: run {
            val request = Request.Builder().url("$ROOT_URL/passport-index-tidy-iso2.csv").build()
            AdmissoryStatus.parse(networkService.send(request).decodeToString()).also { requirements = it }
        }
    }

    private companion object {
        const val ROOT_URL = "https://cdn.jsdelivr.net/gh/ilyankou/passport-index-dataset@master"
    }
}
