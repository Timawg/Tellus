package com.pathos.tellus.guide

import com.pathos.tellus.guide.democracy.AssetDemocracyDatasetStore
import com.pathos.tellus.guide.democracy.DemocracyProfiles
import com.pathos.tellus.guide.exchangerates.CurrencyApiExchangeRateService
import com.pathos.tellus.guide.exchangerates.ExchangeRateService
import com.pathos.tellus.guide.profile.CountryProfileService
import com.pathos.tellus.guide.profile.WorldBankCountryProfileService
import com.pathos.tellus.guide.weather.OpenMeteoWeatherService
import com.pathos.tellus.guide.weather.WeatherService
import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent

@Module
@InstallIn(SingletonComponent::class)
abstract class GuideModule {
    @Binds
    abstract fun bindWeatherService(service: OpenMeteoWeatherService): WeatherService

    @Binds
    abstract fun bindExchangeRateService(service: CurrencyApiExchangeRateService): ExchangeRateService

    @Binds
    abstract fun bindCountryProfileService(service: WorldBankCountryProfileService): CountryProfileService

    @Binds
    abstract fun bindDemocracyProfiles(store: AssetDemocracyDatasetStore): DemocracyProfiles
}
