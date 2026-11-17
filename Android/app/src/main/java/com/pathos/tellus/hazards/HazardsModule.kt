package com.pathos.tellus.hazards

import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent

@Module
@InstallIn(SingletonComponent::class)
abstract class HazardsModule {
    @Binds
    abstract fun bindDisasterAlertService(service: GdacsDisasterAlertService): DisasterAlertService

    @Binds
    abstract fun bindHazardService(service: LiveHazardService): HazardService
}
