# Tellus

Tellus is a world map and travel guide for iPhone and iPad, built with SwiftUI and Apple MapKit. Explore countries, follow aircraft, trace submarine cables, and see which side of Earth is in darkness.

## Explore a country

Tellus starts on a random country. Tap a country on the map, search for it in the country picker, or jump to a neighbouring country from its guide. The map outlines the selected country and zooms to fit it.

The country card shows weather and local time at the capital, exchange rates, and relevant alerts. The **Country guide** has five tabs.

- **Overview** shows population, economy, geography, and infrastructure figures alongside recent events. Each figure includes its observation year and a link to its source. Open **Electricity profile** under **Energy** to see domestic generation by source and net electricity trade for the latest available year. The tab also covers the forecast, exchange rates, connectivity disruptions, emergency numbers, and neighbouring countries.
- **Entry** covers entry advice and visa requirements for the passport selected in Tellus.
- **Health** covers health advice and WHO outbreak reports.
- **Laws** covers local laws and culture.
- **Climate** covers climate and natural hazards, including active disaster alerts.

The passport picker saves your choice on the device. It sets the passport used for visa lookups and the preferred home currency. Without a passport selection, exchange rates use the device region's currency when available.

## Map layers

Open **Map layers** to enable or disable each layer. Tellus remembers the settings on the device.

| Layer | What it shows | Default |
| --- | --- | --- |
| **Live flights** | Aircraft in the visible map area, including military traffic. Tap an aircraft for available flight telemetry, registration, aircraft photo, and route details. | On |
| **Natural hazards** | Earthquakes, tropical cyclones and their tracks, floods, wildfires, droughts, and volcanic eruptions. Tap a marker for details. | On |
| **Undersea cables** | Submarine cable routes and landing points. Tap a cable to see its details and source link. | Off |
| **Power grid** | Mapped power lines, substations, and power plants. Zoom in and tap a feature to see available details and open its OpenStreetMap record. | Off |
| **GPS interference** | Daily GPSJAM cells with elevated or high reports of low aircraft navigation accuracy. Choose a recent UTC day and tap a shaded cell for counts and the source. | Off |
| **Earth at night** | A moving shade over the night hemisphere and a transparent overlay from the latest available daily NOAA-20 Black Marble nighttime imagery. | Off |
| **VIIRS true colour** | Recent NOAA-21 satellite imagery. Starts on the latest date NASA GIBS lists, with a choice of available dates from the past seven UTC days. | Off |

The flight layer polls about every 15 seconds while the map is settled and backs off when OpenSky rate-limits requests. At wide zoom levels, Tellus draws up to 500 aircraft. The natural hazards layer refreshes every 15 minutes while the map is open.

### GPS interference

Tellus fetches GPSJAM’s daily CSV directly when the layer is enabled. It opens on the latest available completed UTC day and lets you select from the previous seven days. Amber and red use GPSJAM’s adjusted thresholds of 2–10% and over 10%, with a minimum of five sampled aircraft per cell. Shading represents reports of degraded aircraft navigation accuracy. Unshaded areas can include sparse or absent ADS-B coverage. [GPSJAM methodology](https://gpsjam.org/faq)

### Earth at night

Tellus calculates the day–night boundary on the device from the current time and updates the shade once a minute. That calculation works offline. The city lights come from a 2016 composite, so they show where lights were observed during that period.

When the layer is enabled, Tellus checks NASA GIBS for the latest available date of its corrected daily NOAA-20 Black Marble imagery and shows that date in UTC. MapKit fetches the visible PNG tiles over HTTPS at native zoom levels 0–8. Tellus renders the grayscale light measurements as a transparent overlay. Some pixels can use older observations to fill gaps. An internet connection is needed to fetch uncached tiles. [NASA Black Marble daily product](https://ladsweb.modaps.eosdis.nasa.gov/missions-and-measurements/products/VJ146A2) · [GIBS tile documentation](https://nasa-gibs.github.io/gibs-api-docs/access-basics/)

**VIIRS true colour** uses the separate `VIIRS_NOAA21_CorrectedReflectance_TrueColor` layer at native zoom levels 0–9. It shows the observation date in UTC. The newest date may have gaps while satellite passes are still being processed. [NOAA-21 VIIRS layer metadata](https://gibs.earthdata.nasa.gov/layer-metadata/v1.0/VIIRS_NOAA21_CorrectedReflectance_TrueColor.json)

## Run locally

- Use **Xcode 26 or later** with the iOS SDK installed. The app targets **iOS and iPadOS 17.5 or later**. Controls use Liquid Glass on iOS and iPadOS 26 or later.
- Open `Tellus.xcodeproj`, select the **Tellus** scheme and an iPhone or iPad simulator, then choose **Product → Run**. To run on a physical device, select your development team under **Signing & Capabilities**.
- The app calls its data providers directly. Running it requires no API keys or Tellus backend. Country data loads over the network at startup. The country boundary geometry ships with the app.
- Xcode resolves the SwiftyH3 package for the GPS interference layer. [SwiftyH3, Apache 2.0](https://github.com/pawelmajcher/SwiftyH3/tree/0.6.0)

To compile from the repository root without signing:

```sh
xcodebuild -project Tellus.xcodeproj -scheme Tellus -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

## Project layout

- The app entry point wires up the network services. [TellusApp.swift](Tellus/TellusApp.swift)
- The main view contains the map controls, country card, and detail sheets. The MapKit wrapper manages annotations and overlays. [MainMapView.swift](Tellus/Views/MainMapView.swift) · [MapRepresentable.swift](Tellus/Views/MapRepresentable.swift)
- The view model coordinates country selection, live data, and map layer state. [MainMapViewModel.swift](Tellus/ViewModels/MainMapViewModel.swift)
- Services fetch and parse the provider feeds. Models and annotations hold the data and map geometry. [Services](Tellus/Network/Services) · [Models](Tellus/Models) · [Annotations](Tellus/Annotations)
- Run the XCTest targets with **Product → Test** on a simulator. [TellusTests](TellusTests) · [TellusUITests](TellusUITests)

### Rebuild the country boundaries

Download the two inputs. [Natural Earth 1:50m country GeoJSON](https://github.com/nvkelso/natural-earth-vector/blob/master/geojson/ne_50m_admin_0_countries.geojson) · [Country metadata JSON](https://cdn.jsdelivr.net/gh/mledoze/countries@master/countries.json)

Run the script from the repository root with Python 3. It matches boundaries to the app's three-letter country codes and regenerates the bundled resource. [country-borders.geojson](Tellus/Resources/country-borders.geojson)

```sh
python3 scripts/build_country_borders.py ne_50m_admin_0_countries.geojson countries.json
```

## Data sources and credits

| Data | Provider |
| --- | --- |
| Basemap | Apple MapKit |
| Country metadata, boundaries, and flags | [mledoze/countries](https://github.com/mledoze/countries), [Natural Earth](https://www.naturalearthdata.com/), and [Flagcdn](https://flagcdn.com/) |
| Country profile figures | [World Bank World Development Indicators](https://datatopics.worldbank.org/world-development-indicators/) |
| Electricity generation mix and net trade | [Ember Yearly Electricity Data](https://ember-energy.org/data/yearly-electricity-data/), CC BY 4.0. Tellus downloads the public CSV when a profile is opened and caches the latest country observations for seven days. |
| Travel advisories and destination guidance | [Government of Canada Travel Advice and Advisories](https://travel.gc.ca/travelling/advisories) |
| Passport-based visa requirements | [Passport Index dataset](https://github.com/ilyankou/passport-index-dataset), served through jsDelivr |
| Capital weather and geocoding | [Open-Meteo](https://open-meteo.com/) |
| Exchange rates | [Fawaz Ahmed's Currency API](https://github.com/fawazahmed0/exchange-api) |
| Recent country events | Wikipedia's year-by-country articles |
| Internet disruptions and disease outbreaks | [IODA](https://ioda.inetintel.cc.gatech.edu/) and [WHO Disease Outbreak News](https://www.who.int/emergencies/disease-outbreak-news) |
| Disaster alerts, earthquakes, and eruptions | [GDACS](https://www.gdacs.org/), [USGS Earthquake Hazards Program](https://earthquake.usgs.gov/earthquakes/feed/), and the [Smithsonian Global Volcanism Program](https://volcano.si.edu/) |
| Aircraft positions | [OpenSky Network](https://opensky-network.org/) and [adsb.lol](https://www.adsb.lol/) |
| Aircraft registration, routes, and photos | [adsbdb](https://www.adsbdb.com/) and [Airport-Data.com](https://www.airport-data.com/) |
| Submarine cables and landing points | [TeleGeography Submarine Cable Map](https://www.submarinecablemap.com/) |
| Power lines, substations, and plants | [Open Infrastructure Map vector tiles](https://openinframap.org/about). Data © [OpenStreetMap contributors](https://www.openstreetmap.org/copyright), ODbL. |
| Aircraft navigation accuracy by area | [GPSJAM](https://gpsjam.org/about), based on reports from airplanes.live and ADS-B Exchange |
| Day–night boundary | [U.S. Naval Observatory solar position calculation](https://aa.usno.navy.mil/faq/sun_approx) |
| Black Marble night lights | [NASA Global Imagery Browse Services (GIBS)](https://nasa-gibs.github.io/gibs-api-docs/), part of NASA's Earth Science Data and Information System (ESDIS) |

Coverage and update times vary by provider. When a destination guide is available, it links to the full Government of Canada advisory.
