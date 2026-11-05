# Tellus

Tellus is a world map and travel guide for iPhone and iPad, built with SwiftUI and Apple MapKit. Explore countries, follow aircraft, trace submarine cables, and see which side of Earth is in darkness.

![Tellus app walkthrough](https://github.com/user-attachments/assets/00da079a-e881-4e0a-afb1-789fc2519c29)

## Explore a country

Tellus starts on a random country. Tap a country on the map, search for it in the country picker, or jump to a neighbouring country from its guide. The map outlines the selected country and zooms to fit it.

The country card shows weather and local time at the capital, exchange rates, and relevant alerts. The **Country guide** has five tabs.

- **Overview** shows population, economy, geography, and infrastructure figures alongside recent events. Each figure includes its observation year and a link to its source. The tab also covers the forecast, exchange rates, connectivity disruptions, emergency numbers, and neighbouring countries.
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
| **Earth at night** | A moving shade over the night hemisphere and a transparent overlay of city lights from NASA's Black Marble 2016 satellite composite. | Off |

The flight layer polls about every 15 seconds while the map is settled and backs off when OpenSky rate-limits requests. At wide zoom levels, Tellus draws up to 500 aircraft. The natural hazards layer refreshes every 15 minutes while the map is open.

### Earth at night

Tellus calculates the day–night boundary on the device from the current time and updates the shade once a minute. That calculation works offline. The city lights come from a 2016 composite, so they show where lights were observed during that period.

When the layer is enabled, MapKit fetches visible PNG tiles directly over HTTPS from NASA GIBS. It uses the `VIIRS_Night_Lights` Web Mercator WMTS layer at native zoom levels 0–8. An internet connection is needed to fetch uncached tiles. [NASA Black Marble imagery](https://science.nasa.gov/earth/earth-observatory/earth-at-night/maps/) · [GIBS tile documentation](https://nasa-gibs.github.io/gibs-api-docs/access-basics/)

## Run locally

- Use **Xcode 26 or later** with the iOS SDK installed. The app targets **iOS and iPadOS 17.5 or later**. Controls use Liquid Glass on iOS and iPadOS 26 or later.
- Open `Tellus.xcodeproj`, select the **Tellus** scheme and an iPhone or iPad simulator, then choose **Product → Run**. To run on a physical device, select your development team under **Signing & Capabilities**.
- The app calls its data providers directly. Running it requires no API keys, dependency installation, or Tellus backend. Country data loads over the network at startup. The country boundary geometry ships with the app.

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
| Day–night boundary | [U.S. Naval Observatory solar position calculation](https://aa.usno.navy.mil/faq/sun_approx) |
| Black Marble night lights | [NASA Global Imagery Browse Services (GIBS)](https://nasa-gibs.github.io/gibs-api-docs/), part of NASA's Earth Science Data and Information System (ESDIS) |

Coverage and update times vary by provider. When a destination guide is available, it links to the full Government of Canada advisory.
