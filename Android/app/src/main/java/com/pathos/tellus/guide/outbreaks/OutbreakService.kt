package com.pathos.tellus.guide.outbreaks

import com.pathos.tellus.core.network.NetworkService
import com.pathos.tellus.countries.Country
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.Request
import java.text.BreakIterator
import java.time.Clock
import java.time.Duration
import java.time.Instant
import java.time.format.DateTimeParseException
import java.util.Locale
import javax.inject.Inject
import javax.inject.Singleton

/** A WHO Disease Outbreak News report. */
data class OutbreakReport(
    val id: String,
    val disease: String,
    /** The places part of the title, e.g. "Democratic Republic of the Congo, Kenya and Nigeria". */
    val places: String,
    val published: Instant,
    /** The first couple of sentences of WHO's summary. */
    val summary: String,
    val url: String?,
)

/** WHO's OData feed: `{"value": [{"Title": …, "PublicationDate": …}]}`. */
@Serializable
data class WhoOutbreakList(val value: List<Item>) {

    @Serializable
    data class Item(
        @SerialName("Title") val title: String,
        @SerialName("PublicationDate") val publicationDate: String,
        @SerialName("UrlName") val urlName: String? = null,
        @SerialName("Summary") val summary: String? = null,
    )

    val reports: List<OutbreakReport>
        get() = value.mapNotNull { item ->
            val published = try {
                Instant.parse(item.publicationDate)
            } catch (_: DateTimeParseException) {
                return@mapNotNull null
            }
            val (disease, places) = split(item.title)
            OutbreakReport(
                id = item.urlName ?: (item.title + item.publicationDate),
                disease = disease,
                places = places,
                published = published,
                summary = shortSummary(item.summary.orEmpty()),
                url = item.urlName?.let { "https://www.who.int/emergencies/disease-outbreak-news/item/$it" },
            )
        }

    // Not private: the serialization plugin adds serializer() to this companion.
    companion object {
        private val separator = Regex("\\s*(?:[–—]|-(?=\\s)|(?<=\\))-)\\s*(?=[^–—]*$)")

        /**
         * Titles read "Nipah virus disease - India", "Avian Influenza
         * A(H5N1)- Cambodia", "Marburg virus disease– United Republic of
         * Tanzania" or "Ebola disease caused by Bundibugyo virus, Democratic
         * Republic of the Congo & Uganda". The separator is the last en or em
         * dash, or a hyphen followed by a space or after a bracket
         * ("A(H5N2)-Mexico"), so names like "Guinea-Bissau" stay whole.
         */
        fun split(title: String): Pair<String, String> {
            val match = separator.find(title)
            if (match != null && match.range.first > 0 && match.range.last + 1 < title.length) {
                return title.substring(0, match.range.first) to title.substring(match.range.last + 1)
            }
            val comma = title.indexOf(',')
            if (comma >= 0) return title.substring(0, comma) to title.substring(comma + 1).trim()
            return title to ""
        }

        /** Up to two sentences, at most about 300 characters. */
        fun shortSummary(text: String): String {
            val plain = text.replace(Regex("<[^>]+>"), "").replace(Regex("\\s+"), " ").trim()
            val iterator = BreakIterator.getSentenceInstance(Locale.ENGLISH).apply { setText(plain) }
            val sentences = mutableListOf<String>()
            var start = iterator.first()
            var end = iterator.next()
            while (end != BreakIterator.DONE && sentences.size < 2) {
                plain.substring(start, end).trim().takeIf { it.isNotEmpty() }?.let(sentences::add)
                start = end
                end = iterator.next()
            }
            val summary = sentences.joinToString(" ")
            return if (summary.length > 300) summary.take(297) + "…" else summary
        }
    }
}

/** Finds which countries each report is about, as iOS `OutbreakCountryMatcher` does. */
object OutbreakCountryMatcher {

    /**
     * Reports per country (ISO alpha-2), keeping only the newest report per
     * disease, newest first. Each report's places are matched once against
     * every country's names, longest first, so "Congo" isn't found inside
     * "Democratic Republic of the Congo" and "Guinea" isn't found inside
     * "Guinea-Bissau".
     */
    fun index(reports: List<OutbreakReport>, countries: List<Country>): Map<String, List<OutbreakReport>> {
        val names = countries.flatMap { country ->
            val code = country.cca2.orEmpty()
            candidateNames(country).map { it.lowercase() to code }
        }.filter { it.second.isNotEmpty() }.sortedByDescending { it.first.length }

        val index = mutableMapOf<String, MutableList<OutbreakReport>>()
        val seen = mutableMapOf<String, MutableSet<String>>()
        for (report in reports.sortedByDescending { it.published }) {
            for (code in matchedCodes(report.places, names)) {
                if (seen.getOrPut(code) { mutableSetOf() }.add(report.disease.lowercase().trim())) {
                    index.getOrPut(code) { mutableListOf() } += report
                }
            }
        }
        return index
    }

    /** Names WHO uses that the country dataset doesn't list. */
    private val whoNames = mapOf(
        "VN" to listOf("Viet Nam"),
        "TR" to listOf("Türkiye", "Turkey"),
        "CI" to listOf("Côte d’Ivoire", "Côte d'Ivoire", "Cote d'Ivoire"),
        "CZ" to listOf("Czechia"),
        "KP" to listOf("Democratic People's Republic of Korea"),
        "LA" to listOf("Lao People's Democratic Republic"),
        "SY" to listOf("Syrian Arab Republic"),
        "MD" to listOf("Republic of Moldova"),
    )

    fun candidateNames(country: Country): List<String> =
        listOfNotNull(country.name?.common, country.name?.official) +
            country.cca2?.let { whoNames[it] }.orEmpty() +
            country.altSpellings.orEmpty().filter { it.length > 3 && it != it.uppercase() }

    /**
     * Substring search with word boundaries checked by hand; much faster than
     * a regex per name. Uses the platform's `indexOf`, since a character-by-
     * character comparison took seconds on a device for WHO's 100 reports.
     */
    private fun matchedCodes(places: String, names: List<Pair<String, String>>): Set<String> {
        val text = StringBuilder(places.lowercase())
        val codes = mutableSetOf<String>()
        for ((name, code) in names) {
            if (name.isEmpty()) continue
            var from = 0
            while (true) {
                val index = text.indexOf(name, from)
                if (index < 0) break
                val end = index + name.length
                if ((index == 0 || !text[index - 1].isLetter()) && (end == text.length || !text[end].isLetter())) {
                    codes += code
                    // Blank it out so shorter names can't match inside it.
                    for (offset in index until end) text.setCharAt(offset, '#')
                    from = end
                } else {
                    from = index + 1
                }
            }
        }
        return codes
    }
}

interface OutbreakService {
    /** WHO's latest Disease Outbreak News reports, newest first. */
    suspend fun getReports(): List<OutbreakReport>
}

/** WHO Disease Outbreak News, which needs no key. One list covers every country, kept for an hour. */
@Singleton
class WhoOutbreakService @Inject constructor(
    private val networkService: NetworkService,
    private val json: Json,
    private val clock: Clock,
) : OutbreakService {

    private val mutex = Mutex()
    private var cache: Pair<Instant, List<OutbreakReport>>? = null

    override suspend fun getReports(): List<OutbreakReport> {
        mutex.withLock { cache }?.let { (fetched, reports) ->
            if (Duration.between(fetched, clock.instant()) < LIFETIME) return reports
        }
        val url = "$ROOT_URL/news/diseaseoutbreaknews".toHttpUrl().newBuilder()
            .addQueryParameter("\$orderby", "PublicationDate desc")
            // The API's maximum page size; about two years of reports.
            .addQueryParameter("\$top", "100")
            .addQueryParameter("\$select", "Title,PublicationDate,UrlName,Summary")
            .build()
        val reports = json.decodeFromString<WhoOutbreakList>(networkService.send(Request.Builder().url(url).build()).decodeToString()).reports
        mutex.withLock { cache = clock.instant() to reports }
        return reports
    }

    private companion object {
        const val ROOT_URL = "https://www.who.int/api"
        val LIFETIME: Duration = Duration.ofHours(1)
    }
}
