# Tellus for Android

A native Kotlin and Jetpack Compose port of the Tellus iOS app, in progress. The port is tracked in [issue #5](https://github.com/Timawg/Tellus/issues/5); [AGENTS.md](../AGENTS.md) lists the conventions.

## Requirements

- JDK 17 or later (Android Studio's bundled JDK works)
- The Android SDK with platform 37
- A Google Maps API key with **Maps SDK for Android** enabled, to see map tiles

## Setup

Create `Android/local.properties` (git-ignored) with your SDK path and Maps key:

```properties
sdk.dir=/Users/you/Library/Android/sdk
MAPS_API_KEY=your-key
```

Without `MAPS_API_KEY` the app still builds, using the placeholder in `local.defaults.properties`, but the map stays blank.

## Build and test

From `Android/`:

```sh
./gradlew test assembleDebug   # unit tests and debug APK
./gradlew installDebug         # install on a connected device or emulator
```

Or open `Android/` in Android Studio and run the `app` configuration.

The country borders and V-Dem datasets are copied from `iOS/` into the app's assets at build time, so regenerate them with the scripts in `scripts/` rather than editing copies.
