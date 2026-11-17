package com.pathos.tellus.guide.events

import com.pathos.tellus.core.network.NetworkService
import com.pathos.tellus.countries.Country
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.Request
import java.time.Clock
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import javax.inject.Inject
import javax.inject.Singleton

interface RecentEventsService {
    /** Recent events from Wikipedia's "<year> in <country>" article, or null if there's no such article. */
    suspend fun getRecentEvents(country: Country): RecentEvents?
}

/**
 * Recent events from English Wikipedia, which needs no key. Wikimedia asks
 * API clients to identify themselves with a User-Agent that includes a
 * contact URL. Results are kept for 30 minutes per country, as on iOS.
 */
@Singleton
class WikipediaRecentEventsService @Inject constructor(
    private val networkService: NetworkService,
    private val json: Json,
    private val clock: Clock,
) : RecentEventsService {

    @Serializable
    private data class QueryResponse(val query: Query) {
        @Serializable
        data class Query(
            val normalized: List<Mapping>? = null,
            val redirects: List<Mapping>? = null,
            val pages: List<Page>,
        )

        @Serializable
        data class Mapping(val from: String, val to: String)

        @Serializable
        data class Page(val title: String, val missing: Boolean? = null, val revisions: List<Revision>? = null)

        @Serializable
        data class Revision(val slots: Slots)

        @Serializable
        data class Slots(val main: Main)

        @Serializable
        data class Main(val content: String? = null)
    }

    private val mutex = Mutex()
    private val cache = mutableMapOf<String, Pair<Instant, RecentEvents?>>()

    override suspend fun getRecentEvents(country: Country): RecentEvents? {
        val key = country.cca2 ?: country.name?.common.orEmpty()
        mutex.withLock { cache[key] }?.let { (fetched, events) ->
            if (Duration.between(fetched, clock.instant()) < LIFETIME) return events
        }

        val today = LocalDate.now(clock)
        val year = today.year
        // Early in the year the new article is still short, so add last year's.
        val years = if (today.monthValue <= 2) listOf(year, year - 1) else listOf(year)
        val candidates = years.map { it to candidateTitles(country, it) }

        val url = "$ROOT_URL/api.php".toHttpUrl().newBuilder()
            .addQueryParameter("action", "query")
            .addQueryParameter("prop", "revisions")
            .addQueryParameter("rvprop", "content")
            .addQueryParameter("rvslots", "main")
            .addQueryParameter("titles", candidates.flatMap { it.second }.joinToString("|"))
            .addQueryParameter("redirects", "1")
            .addQueryParameter("format", "json")
            .addQueryParameter("formatversion", "2")
            .build()
        val request = Request.Builder()
            .url(url)
            .header("User-Agent", USER_AGENT)
            .header("Api-User-Agent", USER_AGENT)
            .build()
        val query = json.decodeFromString<QueryResponse>(networkService.send(request).decodeToString()).query

        val normalized = query.normalized.orEmpty().associate { it.from to it.to }
        val redirects = query.redirects.orEmpty().associate { it.from to it.to }
        val pages = query.pages.filter { it.missing != true }.associateBy { it.title }

        val events = mutableListOf<RecentEvent>()
        var articleTitle: String? = null
        for ((candidateYear, titles) in candidates) {
            // The first candidate that exists, after normalising and redirects.
            val page = titles.firstNotNullOfOrNull { title ->
                val normal = normalized[title] ?: title
                pages[redirects[normal] ?: normal]
            } ?: continue
            val text = page.revisions?.firstOrNull()?.slots?.main?.content ?: continue
            articleTitle = articleTitle ?: page.title
            events += WikipediaEventsParser.events(text, candidateYear, today)
        }

        val result = articleTitle?.let { title ->
            RecentEvents(events.mapIndexed { index, event -> event.copy(id = index) }, title)
        }
        mutex.withLock { cache[key] = clock.instant() to result }
        return result
    }

    companion object {
        private const val ROOT_URL = "https://en.wikipedia.org/w"
        private val LIFETIME: Duration = Duration.ofMinutes(30)
        const val USER_AGENT = "Tellus/1.0 (https://github.com/Timawg/Tellus)"

        /** Countries whose article doesn't follow the usual names. */
        private val titleOverrides = mapOf("TR" to "Turkey", "GE" to "Georgia (country)")

        /** "2026 in Kenya", "2026 in the Bahamas", "2026 in the Czech Republic"… */
        fun candidateTitles(country: Country, year: Int): List<String> {
            val names = mutableListOf<String>()
            country.cca2?.let { titleOverrides[it] }?.let { names += it }
            for (name in listOfNotNull(country.name?.common, country.name?.official)) {
                names += name
                names += "the $name"
            }
            return names.distinct().map { "$year in $it" }
        }
    }
}
