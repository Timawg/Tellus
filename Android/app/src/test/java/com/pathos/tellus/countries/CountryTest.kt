package com.pathos.tellus.countries

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class CountryTest {

    private fun country(idd: Country.Idd? = null, currencies: Map<String, Country.CurrencyInfo>? = null) =
        Country(idd = idd, currencies = currencies, translations = emptyMap(), latlng = emptyList())

    @Test
    fun callingCodeJoinsSingleSuffixOnly() {
        assertEquals("+46", country(Country.Idd("+4", listOf("6"))).callingCode)
        assertEquals("+1", country(Country.Idd("+1", listOf("201", "202"))).callingCode)
        assertNull(country(Country.Idd("", listOf("6"))).callingCode)
        assertNull(country().callingCode)
    }

    @Test
    fun currencyDescriptionsPreferSymbolOverRepeatedCode() {
        val described = country(
            currencies = mapOf(
                "SEK" to Country.CurrencyInfo("Swedish krona", "kr"),
                "CHF" to Country.CurrencyInfo("Swiss franc", "CHF"),
                "XXX" to Country.CurrencyInfo(null, null),
            ),
        ).currencyDescriptions
        assertEquals(listOf("Swiss franc (CHF)", "Swedish krona (kr)", "XXX (XXX)"), described)
    }
}
