package com.pathos.tellus.countries

import kotlinx.serialization.Serializable

/**
 * A country from the mledoze/countries dataset. Mirrors iOS `Country`:
 * `translations` and `latlng` are required there too, so an entry missing
 * them fails the whole list rather than showing a half-empty country.
 */
@Serializable
data class Country(
    val name: Name? = null,
    val tld: List<String>? = null,
    val cca2: String? = null,
    val ccn3: String? = null,
    val cca3: String? = null,
    val cioc: String? = null,
    val independent: Boolean? = null,
    val status: String? = null,
    val unMember: Boolean? = null,
    /** Keyed by ISO 4217 code, e.g. "SEK". */
    val currencies: Map<String, CurrencyInfo>? = null,
    val idd: Idd? = null,
    val capital: List<String>? = null,
    val altSpellings: List<String>? = null,
    val region: String? = null,
    val subregion: String? = null,
    /** Language names keyed by ISO 639-3 code, e.g. "swe": "Swedish". */
    val languages: Map<String, String>? = null,
    val translations: Map<String, Translation>,
    val latlng: List<Double>,
    val landlocked: Boolean? = null,
    val borders: List<String>? = null,
    val area: Double? = null,
    val demonyms: Demonyms? = null,
    val flag: String? = null,
    val maps: Maps? = null,
    val population: Long? = null,
    val fifa: String? = null,
    val car: Car? = null,
    val timezones: List<String>? = null,
    val continents: List<String>? = null,
    val flags: Images? = null,
    val coatOfArms: Images? = null,
    val startOfWeek: String? = null,
    val capitalInfo: CapitalInfo? = null,
) {
    /**
     * Flag image URL. The dataset only provides an emoji flag, so the PNG is
     * derived from the alpha-2 code via flagcdn, unless `flags.png` is present.
     */
    val flagUrl: String?
        get() = flags?.png ?: cca2?.let { "https://flagcdn.com/w320/${it.lowercase()}.png" }

    /** "Swedish krona (kr)", one per currency. */
    val currencyDescriptions: List<String>
        get() = currencies.orEmpty().toSortedMap().map { (code, currency) ->
            val name = currency.name ?: code
            val symbol = currency.symbol
            if (symbol != null && symbol != code) "$name ($symbol)" else "$name ($code)"
        }

    val languageNames: List<String>
        get() = languages.orEmpty().values.sorted()

    /**
     * International dialling code, e.g. "+46". Countries sharing a root with
     * many suffixes (like +1 for North America) show just the root.
     */
    val callingCode: String?
        get() {
            val root = idd?.root?.takeIf { it.isNotEmpty() } ?: return null
            val suffixes = idd.suffixes
            return if (suffixes?.size == 1) root + suffixes[0] else root
        }

    @Serializable
    data class Name(val common: String? = null, val official: String? = null)

    @Serializable
    data class Translation(val official: String? = null, val common: String? = null)

    @Serializable
    data class CurrencyInfo(val name: String? = null, val symbol: String? = null)

    @Serializable
    data class Idd(val root: String? = null, val suffixes: List<String>? = null)

    @Serializable
    data class Demonyms(val eng: Demonym? = null, val fra: Demonym? = null)

    @Serializable
    data class Demonym(val f: String? = null, val m: String? = null)

    @Serializable
    data class Maps(val googleMaps: String? = null, val openStreetMaps: String? = null)

    @Serializable
    data class Car(val signs: List<String>? = null, val side: String? = null)

    @Serializable
    data class Images(val png: String? = null, val svg: String? = null)

    @Serializable
    data class CapitalInfo(val latlng: List<Double>? = null)
}
