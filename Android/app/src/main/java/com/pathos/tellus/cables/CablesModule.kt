package com.pathos.tellus.cables

import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent

@Module
@InstallIn(SingletonComponent::class)
abstract class CablesModule {
    @Binds
    abstract fun bindCableService(service: SubmarineCableMapService): CableService
}
