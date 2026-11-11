//
//  Weather.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2026-11-04.
//

import Foundation

/// Open-Meteo forecast response.
struct WeatherForecast: Decodable {

    struct Current: Decodable {
        let temperature: Double
        let apparentTemperature: Double
        let weatherCode: Int
        let isDay: Int
        let windSpeed: Double
        let relativeHumidity: Int

        enum CodingKeys: String, CodingKey {
            case temperature = "temperature_2m"
            case apparentTemperature = "apparent_temperature"
            case weatherCode = "weather_code"
            case isDay = "is_day"
            case windSpeed = "wind_speed_10m"
            case relativeHumidity = "relative_humidity_2m"
        }
    }

    struct Daily: Decodable {
        let time: [String]
        let weatherCode: [Int]
        let temperatureMax: [Double]
        let temperatureMin: [Double]

        enum CodingKeys: String, CodingKey {
            case time
            case weatherCode = "weather_code"
            case temperatureMax = "temperature_2m_max"
            case temperatureMin = "temperature_2m_min"
        }
    }

    let utcOffsetSeconds: Int
    let timezone: String
    let current: Current
    let daily: Daily

    enum CodingKeys: String, CodingKey {
        case utcOffsetSeconds = "utc_offset_seconds"
        case timezone, current, daily
    }
}

/// Open-Meteo geocoding response.
struct GeocodingResult: Decodable {
    struct Place: Decodable {
        let name: String
        let latitude: Double
        let longitude: Double
        /// GeoNames feature code: "PPLC" for a capital, "PPL…" for other
        /// populated places, "AIRP" for airports and so on.
        let featureCode: String?

        enum CodingKeys: String, CodingKey {
            case name, latitude, longitude
            case featureCode = "feature_code"
        }

        var isPopulatedPlace: Bool {
            featureCode?.hasPrefix("PPL") == true
        }
    }
    let results: [Place]?
}

/// Current weather and the next few days at a destination's capital.
struct DestinationWeather: Equatable {

    struct Day: Equatable, Identifiable {
        let date: Date
        let condition: WeatherCondition
        let high: Double
        let low: Double
        var id: Date { date }
    }

    /// Where the weather is for: the capital, or the country itself when the
    /// capital couldn't be located.
    let placeName: String
    let timeZone: TimeZone
    let condition: WeatherCondition
    let isDay: Bool
    /// Degrees Celsius.
    let temperature: Double
    let feelsLike: Double
    /// Kilometres per hour.
    let windSpeed: Double
    let humidity: Int
    let days: [Day]

    init(placeName: String, forecast: WeatherForecast) {
        self.placeName = placeName
        timeZone = TimeZone(identifier: forecast.timezone)
            ?? TimeZone(secondsFromGMT: forecast.utcOffsetSeconds)
            ?? .current
        condition = WeatherCondition(code: forecast.current.weatherCode)
        isDay = forecast.current.isDay == 1
        temperature = forecast.current.temperature
        feelsLike = forecast.current.apparentTemperature
        windSpeed = forecast.current.windSpeed
        humidity = forecast.current.relativeHumidity

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        let daily = forecast.daily
        let count = [daily.time.count, daily.weatherCode.count, daily.temperatureMax.count, daily.temperatureMin.count].min() ?? 0
        days = (0..<count).compactMap { index in
            formatter.date(from: daily.time[index]).map {
                Day(date: $0,
                    condition: WeatherCondition(code: daily.weatherCode[index]),
                    high: daily.temperatureMax[index],
                    low: daily.temperatureMin[index])
            }
        }
    }

    var symbolName: String {
        condition.symbolName(isDay: isDay)
    }

    /// "16:01" at the destination. Formatted to a string up front because
    /// SwiftUI's `Text(_:format:)` swaps in the device's own time zone.
    func localTime(at date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone))
    }

    /// "10°", in Celsius or Fahrenheit depending on the device's region.
    static func temperatureText(_ celsius: Double) -> String {
        Measurement(value: celsius, unit: UnitTemperature.celsius)
            .formatted(.measurement(width: .narrow, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0))))
    }

    /// "5 km/h" or "3 mph" depending on the device's region.
    static func windText(_ kilometresPerHour: Double) -> String {
        Measurement(value: kilometresPerHour, unit: UnitSpeed.kilometersPerHour)
            .formatted(.measurement(width: .abbreviated, usage: .wind, numberFormatStyle: .number.precision(.fractionLength(0))))
    }
}

/// WMO weather interpretation codes, as used by Open-Meteo, grouped into
/// what a traveller cares about.
enum WeatherCondition: Equatable {
    case clear, partlyCloudy, overcast, fog, drizzle, rain, heavyRain
    case freezingRain, snow, showers, thunderstorm, unknown

    init(code: Int) {
        switch code {
        case 0, 1: self = .clear
        case 2: self = .partlyCloudy
        case 3: self = .overcast
        case 45, 48: self = .fog
        case 51...57: self = .drizzle
        case 61, 63: self = .rain
        case 65: self = .heavyRain
        case 66, 67: self = .freezingRain
        case 71...77, 85, 86: self = .snow
        case 80...82: self = .showers
        case 95...99: self = .thunderstorm
        default: self = .unknown
        }
    }

    var description: String {
        switch self {
        case .clear: "Clear"
        case .partlyCloudy: "Partly cloudy"
        case .overcast: "Cloudy"
        case .fog: "Fog"
        case .drizzle: "Drizzle"
        case .rain: "Rain"
        case .heavyRain: "Heavy rain"
        case .freezingRain: "Freezing rain"
        case .snow: "Snow"
        case .showers: "Showers"
        case .thunderstorm: "Thunderstorms"
        case .unknown: "Unknown"
        }
    }

    /// SF Symbol, with a night variant where one exists.
    func symbolName(isDay: Bool = true) -> String {
        switch self {
        case .clear: isDay ? "sun.max.fill" : "moon.stars.fill"
        case .partlyCloudy: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case .overcast: "cloud.fill"
        case .fog: "cloud.fog.fill"
        case .drizzle: "cloud.drizzle.fill"
        case .rain: "cloud.rain.fill"
        case .heavyRain: "cloud.heavyrain.fill"
        case .freezingRain: "cloud.sleet.fill"
        case .snow: "cloud.snow.fill"
        case .showers: isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        case .thunderstorm: "cloud.bolt.rain.fill"
        case .unknown: "questionmark.circle"
        }
    }
}
