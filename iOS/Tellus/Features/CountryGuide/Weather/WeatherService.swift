//
//  WeatherService.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2026-11-04.
//

import Foundation

protocol WeatherServiceProtocol: Service {
    func getWeather(for country: Country) async throws -> DestinationWeather
}

/// Weather at a country's capital from Open-Meteo, which is free for
/// non-commercial use and needs no API key. Capitals are located with
/// Open-Meteo's geocoding API; when that fails, the country's centre is used.
/// Locations are cached for the session and forecasts for 15 minutes.
actor WeatherService: WeatherServiceProtocol {

    let networkService: NetworkServiceProtocol
    let requestFactory: URLRequestFactory

    private struct Location {
        let name: String
        let latitude: Double
        let longitude: Double
    }

    private var locations: [String: Location] = [:]
    private var forecasts: [String: (fetched: Date, weather: DestinationWeather)] = [:]
    private static let forecastLifetime: TimeInterval = 15 * 60

    init(networkService: NetworkServiceProtocol, requestFactory: URLRequestFactory = .default) {
        self.networkService = networkService
        self.requestFactory = requestFactory
    }

    nonisolated let rootURL: String = "https://api.open-meteo.com/v1"
    nonisolated let geocodingRootURL: String = "https://geocoding-api.open-meteo.com/v1"

    enum WeatherEndpoint: Endpoint {
        case forecast(latitude: Double, longitude: Double)
        case search(name: String, countryCode: String)

        var path: String {
            switch self {
            case .forecast: "/forecast"
            case .search: "/search"
            }
        }

        var httpMethod: HTTPMethod {
            return .get
        }

        var queryItems: [URLQueryItem]? {
            switch self {
            case .forecast(let latitude, let longitude):
                [
                    .init(name: "latitude", value: String(format: "%.3f", latitude)),
                    .init(name: "longitude", value: String(format: "%.3f", longitude)),
                    .init(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day,wind_speed_10m,relative_humidity_2m"),
                    .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min"),
                    .init(name: "timezone", value: "auto"),
                    .init(name: "forecast_days", value: "4"),
                ]
            case .search(let name, let countryCode):
                [
                    .init(name: "name", value: name),
                    .init(name: "countryCode", value: countryCode),
                    .init(name: "count", value: "10"),
                ]
            }
        }

        var cachePolicy: URLRequest.CachePolicy {
            // Forecasts change; this service keeps its own short cache instead.
            if case .forecast = self { return .reloadIgnoringLocalCacheData }
            return .useProtocolCachePolicy
        }
    }

    private static let decoder = JSONDecoder()

    func getWeather(for country: Country) async throws -> DestinationWeather {
        let location = try await location(for: country)
        let key = String(format: "%.3f,%.3f", location.latitude, location.longitude)
        if let cached = forecasts[key], Date().timeIntervalSince(cached.fetched) < Self.forecastLifetime {
            return cached.weather
        }
        let request = try requestFactory.createURLRequest(
            root: rootURL,
            endpoint: WeatherEndpoint.forecast(latitude: location.latitude, longitude: location.longitude)
        )
        let data: Data = try await networkService.send(request: request)
        let forecast = try Self.decoder.decode(WeatherForecast.self, from: data)
        let weather = DestinationWeather(placeName: location.name, forecast: forecast)
        forecasts[key] = (Date(), weather)
        return weather
    }

    private func location(for country: Country) async throws -> Location {
        let key = country.cca2 ?? country.name?.common ?? ""
        if let cached = locations[key] {
            return cached
        }
        var location: Location?
        if let capital = country.capital?.first, let code = country.cca2 {
            for name in Self.searchNames(for: capital) where location == nil {
                location = try await search(name: name, countryCode: code)
                    .map { Location(name: capital, latitude: $0.latitude, longitude: $0.longitude) }
            }
        }
        if location == nil, country.latlng.count == 2 {
            location = Location(name: country.name?.common ?? "", latitude: country.latlng[0], longitude: country.latlng[1])
        }
        guard let location else { throw HTTPError.invalidResponse }
        locations[key] = location
        return location
    }

    /// The best populated place with this name: the capital if it's tagged
    /// as one, otherwise the first town or city. Airports and other features
    /// sharing the name are ignored.
    private func search(name: String, countryCode: String) async throws -> GeocodingResult.Place? {
        let request = try requestFactory.createURLRequest(
            root: geocodingRootURL,
            endpoint: WeatherEndpoint.search(name: name, countryCode: countryCode)
        )
        let data: Data = try await networkService.send(request: request)
        let places = try Self.decoder.decode(GeocodingResult.self, from: data).results ?? []
        return places.first { $0.featureCode == "PPLC" } ?? places.first(where: \.isPopulatedPlace)
    }

    /// Spellings to try for a capital. The dataset sometimes uses long
    /// official names ("City of San Marino") or apostrophes the geocoder
    /// doesn't match ("Sana'a" only finds the airport; "Sanaa" finds the city).
    static func searchNames(for capital: String) -> [String] {
        var names = [capital]
        for prefix in ["City of ", "South "] where capital.hasPrefix(prefix) {
            names.append(String(capital.dropFirst(prefix.count)))
        }
        for name in names where name.contains(where: { "'’".contains($0) }) {
            names.append(name.filter { !"'’".contains($0) })
        }
        return names
    }
}
