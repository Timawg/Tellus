package com.pathos.tellus.countries

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class CountrySearchTest {

    private fun country(common: String, official: String = common) =
        Country(name = Country.Name(common, official), cca3 = common.take(3).uppercase(), translations = emptyMap(), latlng = emptyList())

    private val india = country("India", "Republic of India")
    private val biot = country("British Indian Ocean Territory")
    private val ivoryCoast = country("Ivory Coast", "Republic of Côte d'Ivoire")
    private val aland = country("Åland Islands")
    private val all = listOf(aland, biot, india, ivoryCoast)

    @Test
    fun blankQueryShowsEverything() {
        assertEquals(all, CountrySearch.filter(all, "  "))
    }

    @Test
    fun matchingIgnoresCaseAndAccents() {
        assertEquals(listOf(aland), CountrySearch.filter(all, "aland"))
        assertEquals(listOf(ivoryCoast), CountrySearch.filter(all, "COTE D"))
    }

    @Test
    fun matchesOfficialName() {
        assertEquals(listOf(india, ivoryCoast), CountrySearch.filter(all, "republic"))
    }

    @Test
    fun submitPicksExactMatchAmongSeveral() {
        assertEquals(listOf(biot, india), CountrySearch.filter(all, "india"))
        assertEquals(india, CountrySearch.submitted(all, " India "))
    }

    @Test
    fun submitPicksOnlyMatch() {
        assertEquals(aland, CountrySearch.submitted(all, "åla"))
    }

    @Test
    fun submitWithAmbiguousQueryPicksNothing() {
        assertNull(CountrySearch.submitted(all, "republic"))
        assertNull(CountrySearch.submitted(all, "zzz"))
    }
}
