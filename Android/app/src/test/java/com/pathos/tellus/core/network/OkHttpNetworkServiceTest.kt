package com.pathos.tellus.core.network

import kotlinx.coroutines.test.runTest
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class OkHttpNetworkServiceTest {

    private val request = Request.Builder().url("https://example.test/data").build()

    /** A service whose client answers every request locally with the given response. */
    private fun service(code: Int, body: String = "", headers: Map<String, String> = emptyMap()): OkHttpNetworkService {
        val client = OkHttpClient.Builder()
            .addInterceptor(Interceptor { chain ->
                Response.Builder()
                    .request(chain.request())
                    .protocol(Protocol.HTTP_1_1)
                    .code(code)
                    .message("")
                    .apply { headers.forEach { (name, value) -> header(name, value) } }
                    .body(body.toResponseBody())
                    .build()
            })
            .build()
        return OkHttpNetworkService(client)
    }

    private suspend fun sendExpectingError(service: OkHttpNetworkService): HttpError {
        try {
            service.send(request)
        } catch (error: HttpError) {
            return error
        }
        fail("Expected an HttpError")
        error("unreachable")
    }

    @Test
    fun successReturnsBody() = runTest {
        val body = service(200, "hello").send(request)
        assertArrayEquals("hello".toByteArray(), body)
    }

    @Test
    fun rateLimitReadsRetryAfter() = runTest {
        val error = sendExpectingError(service(429, headers = mapOf("Retry-After" to " 120 ")))
        assertTrue(error is HttpError.RateLimited)
        assertEquals(120.0, (error as HttpError.RateLimited).retryAfterSeconds!!, 0.0)
    }

    @Test
    fun rateLimitFallsBackToOpenSkyHeader() = runTest {
        val error = sendExpectingError(service(429, headers = mapOf("X-Rate-Limit-Retry-After-Seconds" to "30")))
        assertEquals(30.0, (error as HttpError.RateLimited).retryAfterSeconds!!, 0.0)
    }

    @Test
    fun rateLimitWithoutHeaderHasNoWait() = runTest {
        val error = sendExpectingError(service(429))
        assertNull((error as HttpError.RateLimited).retryAfterSeconds)
    }

    @Test
    fun nonSuccessStatusCarriesCodeAndBody() = runTest {
        val error = sendExpectingError(service(503, "down"))
        val invalid = error as HttpError.InvalidStatus
        assertEquals(503, invalid.code)
        assertArrayEquals("down".toByteArray(), invalid.body)
    }
}
