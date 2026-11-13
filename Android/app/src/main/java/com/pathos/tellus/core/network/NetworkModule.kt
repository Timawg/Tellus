package com.pathos.tellus.core.network

import android.content.Context
import dagger.Binds
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import kotlinx.serialization.json.Json
import okhttp3.Cache
import okhttp3.OkHttpClient
import java.io.File
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
abstract class NetworkModule {

    @Binds
    abstract fun bindNetworkService(service: OkHttpNetworkService): NetworkService

    companion object {
        // Matches the iOS URLCache disk capacity.
        private const val CACHE_SIZE_BYTES = 100L * 1024 * 1024

        // One client for the whole app, so every request shares the same
        // connection pool and on-disk cache.
        @Provides
        @Singleton
        fun provideOkHttpClient(@ApplicationContext context: Context): OkHttpClient =
            OkHttpClient.Builder()
                .cache(Cache(File(context.cacheDir, "http"), CACHE_SIZE_BYTES))
                .build()

        // Provider payloads carry fields we don't model, so ignore them rather than fail.
        @Provides
        @Singleton
        fun provideJson(): Json = Json { ignoreUnknownKeys = true }
    }
}
