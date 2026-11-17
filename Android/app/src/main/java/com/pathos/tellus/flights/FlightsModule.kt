package com.pathos.tellus.flights

import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent

@Module
@InstallIn(SingletonComponent::class)
abstract class FlightsModule {
    @Binds
    abstract fun bindFlightService(service: OpenSkyFlightService): FlightService

    @Binds
    abstract fun bindFlightDetailsService(service: AdsbdbFlightDetailsService): FlightDetailsService
}
