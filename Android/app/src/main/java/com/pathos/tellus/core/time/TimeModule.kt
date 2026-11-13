package com.pathos.tellus.core.time

import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import java.time.Clock
import java.util.Locale

/** The clock and locale, read at this boundary so services and view models can be tested with fixed ones. */
@Module
@InstallIn(SingletonComponent::class)
object TimeModule {
    @Provides
    fun provideClock(): Clock = Clock.systemDefaultZone()

    // Unscoped, so a locale change is picked up the next time it's injected.
    @Provides
    fun provideLocale(): Locale = Locale.getDefault()
}
