package com.pathos.tellus.guide

import com.pathos.tellus.guide.democracy.AssetDemocracyDatasetStore
import com.pathos.tellus.guide.democracy.DemocracyProfiles
import com.pathos.tellus.guide.exchangerates.CurrencyApiExchangeRateService
import com.pathos.tellus.guide.exchangerates.ExchangeRateService
import com.pathos.tellus.guide.profile.CountryProfileService
import com.pathos.tellus.guide.profile.WorldBankCountryProfileService
import com.pathos.tellus.guide.weather.OpenMeteoWeatherService
import com.pathos.tellus.guide.weather.WeatherService
import android.content.Context
import com.pathos.tellus.guide.electricity.ElectricityService
import com.pathos.tellus.guide.electricity.EmberCacheFile
import com.pathos.tellus.guide.electricity.EmberElectricityService
import com.pathos.tellus.guide.events.RecentEventsService
import com.pathos.tellus.guide.events.WikipediaRecentEventsService
import com.pathos.tellus.guide.outages.InternetOutageService
import com.pathos.tellus.guide.outages.IodaInternetOutageService
import com.pathos.tellus.guide.prices.EurostatPriceService
import com.pathos.tellus.guide.prices.PriceLevelService
import dagger.Binds
import dagger.Module
import dagger.Provides
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import java.io.File

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

    @Binds
    abstract fun bindInternetOutageService(service: IodaInternetOutageService): InternetOutageService

    @Binds
    abstract fun bindRecentEventsService(service: WikipediaRecentEventsService): RecentEventsService

    @Binds
    abstract fun bindPriceLevelService(service: EurostatPriceService): PriceLevelService

    @Binds
    abstract fun bindElectricityService(service: EmberElectricityService): ElectricityService

    companion object {
        @Provides
        @EmberCacheFile
        fun provideEmberCacheFile(@ApplicationContext context: Context): File? =
            File(context.cacheDir, "ember-electricity-v1.json")
    }
}
