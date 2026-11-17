package com.pathos.tellus.guide.advisories

import com.pathos.tellus.core.network.NetworkService
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.CacheControl
import okhttp3.Request
import javax.inject.Inject
import javax.inject.Singleton

/**
 * A Government of Canada travel advisory. Only the fields the guide shows are
 * decoded, and they're required as on iOS; iOS also requires fields it never
 * reads (offices, metadata), which this leaves out so they can't fail a load.
 */
@Serializable
data class AdvisoryStatus(val data: Data) {

    @Serializable
    data class Data(
        @SerialName("country-iso") val countryIso: String,
        @SerialName("advisory-state") val advisoryState: Int,
        val eng: Information,
    ) {
        /** The four advisory levels, in increasing severity. */
        val state: State? get() = State.entries.getOrNull(advisoryState)
    }

    enum class State { SECURE, CAUTION, AVOID, DANGER }

    @Serializable
    data class Information(
        val name: String,
        @SerialName("url-slug") val urlSlug: String,
        @SerialName("friendly-date") val friendlyDate: String,
        @SerialName("advisory-text") val advisoryText: String,
        val advisories: String,
        @SerialName("entry-exit") val entryExit: String,
        val health: String,
        @SerialName("laws-culture") val lawsCulture: String,
        @SerialName("disasters-climate") val disastersClimate: String,
        @SerialName("offices-html") val officesHtml: String,
    ) {
        /** Advice page on travel.gc.ca, which the API data comes from. */
        val travelAdviceUrl: String get() = "https://travel.gc.ca/destinations/$urlSlug"
    }
}

interface AdvisoryService {
    suspend fun getAdvisoryStatus(destination: String): AdvisoryStatus
}

/** Advisories from Global Affairs Canada's open data, revalidated on every request as on iOS. */
@Singleton
class GacAdvisoryService @Inject constructor(
    private val networkService: NetworkService,
    private val json: Json,
) : AdvisoryService {

    override suspend fun getAdvisoryStatus(destination: String): AdvisoryStatus {
        val request = Request.Builder()
            .url("$ROOT_URL/cta-cap-$destination.json")
            .cacheControl(CacheControl.Builder().noCache().build())
            .build()
        return json.decodeFromString(networkService.send(request).decodeToString())
    }

    private companion object {
        const val ROOT_URL = "https://data.international.gc.ca/travel-voyage"
    }
}
