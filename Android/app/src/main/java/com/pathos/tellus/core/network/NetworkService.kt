package com.pathos.tellus.core.network

import kotlinx.coroutines.suspendCancellableCoroutine
import okhttp3.Call
import okhttp3.Callback
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import java.io.IOException
import javax.inject.Inject
import kotlin.coroutines.resumeWithException

/** Sends HTTP requests for the feature services. Mirrors iOS `NetworkServiceProtocol`. */
interface NetworkService {
    /** Returns the body of a 2xx response, or throws [HttpError] or [IOException]. */
    suspend fun send(request: Request): ByteArray
}

sealed class HttpError(message: String) : Exception(message) {
    /** HTTP 429. [retryAfterSeconds] is the server's requested wait, when it sent one. */
    class RateLimited(val retryAfterSeconds: Double?) : HttpError("Rate limited")

    class InvalidStatus(val code: Int, val body: ByteArray) : HttpError("HTTP $code")
}

class OkHttpNetworkService @Inject constructor(
    private val client: OkHttpClient,
) : NetworkService {

    // The whole response, body included, is read on OkHttp's thread in the
    // callback. Reading the body after resuming ran it on the caller's
    // thread, which is the main thread for view models, and Android rejects
    // that with NetworkOnMainThreadException.
    override suspend fun send(request: Request): ByteArray = suspendCancellableCoroutine { continuation ->
        val call = client.newCall(request)
        continuation.invokeOnCancellation { call.cancel() }
        call.enqueue(object : Callback {
            override fun onResponse(call: Call, response: Response) {
                val result = try {
                    response.use { Result.success(bodyOrError(it)) }
                } catch (error: IOException) {
                    Result.failure(error)
                } catch (error: HttpError) {
                    Result.failure(error)
                }
                continuation.resumeWith(result)
            }

            override fun onFailure(call: Call, e: IOException) {
                continuation.resumeWithException(e)
            }
        })
    }

    private companion object {
        fun bodyOrError(response: Response): ByteArray {
            val body = response.body.bytes()
            return when {
                response.code == 429 -> throw HttpError.RateLimited(retryAfterSeconds(response))
                !response.isSuccessful -> throw HttpError.InvalidStatus(response.code, body)
                else -> body
            }
        }

        /**
         * Seconds the server asked us to wait, from the standard `Retry-After`
         * header (seconds form) or OpenSky's `X-Rate-Limit-Retry-After-Seconds`.
         */
        fun retryAfterSeconds(response: Response): Double? =
            (response.header("Retry-After") ?: response.header("X-Rate-Limit-Retry-After-Seconds"))
                ?.trim()
                ?.toDoubleOrNull()
    }
}
