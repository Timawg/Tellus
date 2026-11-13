package com.pathos.tellus.countries

import java.text.Normalizer
import java.util.Locale

/** Matching for the country search field, mirroring the iOS selection bar. */
object CountrySearch {

    /** Whether the common or official name contains [query], ignoring case and accents. */
    fun matches(country: Country, query: String): Boolean {
        val folded = fold(query)
        return listOfNotNull(country.name?.common, country.name?.official).any { fold(it).contains(folded) }
    }

    /** Whether the common name is exactly [query], ignoring case and accents. */
    fun isExactMatch(country: Country, query: String): Boolean =
        country.name?.common?.let { fold(it) == fold(query) } == true

    /** The countries shown for [query]: all of them when it's blank. */
    fun filter(countries: List<Country>, query: String): List<Country> {
        val trimmed = query.trim()
        if (trimmed.isEmpty()) return countries
        return countries.filter { matches(it, trimmed) }
    }

    /**
     * What submitting the search picks: the only match, or the one exact
     * match among several ("India" over "British Indian Ocean Territory").
     */
    fun submitted(countries: List<Country>, query: String): Country? {
        val trimmed = query.trim()
        val visible = filter(countries, trimmed)
        if (visible.size == 1) return visible[0]
        return visible.filter { isExactMatch(it, trimmed) }.singleOrNull()
    }

    private val combiningMarks = Regex("\\p{Mn}+")

    private fun fold(text: String): String =
        combiningMarks.replace(Normalizer.normalize(text, Normalizer.Form.NFD), "").lowercase(Locale.ROOT)
}
