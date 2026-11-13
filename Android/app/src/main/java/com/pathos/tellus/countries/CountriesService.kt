package com.pathos.tellus.countries

import com.pathos.tellus.core.network.NetworkService
import kotlinx.serialization.json.Json
import okhttp3.Request
import javax.inject.Inject

interface CountriesService {
    suspend fun getAllCountries(): List<Country>
}

/**
 * Reads the open dataset RestCountries is built from (mledoze/countries),
 * served over the jsDelivr CDN, as iOS `CountriesService` does. Caching
 * follows the server's headers.
 */
class JsDelivrCountriesService @Inject constructor(
    private val networkService: NetworkService,
    private val json: Json,
) : CountriesService {

    override suspend fun getAllCountries(): List<Country> {
        val request = Request.Builder().url("$ROOT_URL/countries.json").build()
        val body = networkService.send(request)
        return json.decodeFromString(body.decodeToString())
    }

    private companion object {
        const val ROOT_URL = "https://cdn.jsdelivr.net/gh/mledoze/countries@master"
    }
}
