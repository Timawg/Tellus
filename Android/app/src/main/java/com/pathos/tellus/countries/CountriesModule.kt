package com.pathos.tellus.countries

import dagger.Binds
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import kotlin.random.Random

@Module
@InstallIn(SingletonComponent::class)
abstract class CountriesModule {

    @Binds
    abstract fun bindCountriesService(service: JsDelivrCountriesService): CountriesService

    @Binds
    abstract fun bindCountryBordersLoader(loader: AssetCountryBordersLoader): CountryBordersLoader

    companion object {
        // Picks the random country; injected so tests can make it predictable.
        @Provides
        fun provideRandom(): Random = Random.Default
    }
}
