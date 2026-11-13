package com.pathos.tellus.testing

import com.pathos.tellus.core.network.NetworkService
import okhttp3.Request
import java.time.Clock
import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset

/** Answers each request with the first route whose URL contains its key, and records what was asked. */
class FakeNetworkService(private val routes: Map<String, (Request) -> String>) : NetworkService {
    val requests = mutableListOf<Request>()

    override suspend fun send(request: Request): ByteArray {
        requests += request
        val url = request.url.toString()
        val route = routes.entries.firstOrNull { url.contains(it.key) } ?: error("No fixture for $url")
        return route.value(request).toByteArray()
    }

    fun count(fragment: String) = requests.count { it.url.toString().contains(fragment) }
}

/** A clock the test can move. */
class MutableClock(var now: Instant = Instant.parse("2026-11-13T12:00:00Z")) : Clock() {
    override fun getZone(): ZoneId = ZoneOffset.UTC
    override fun withZone(zone: ZoneId?): Clock = this
    override fun instant(): Instant = now
}
