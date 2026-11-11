import SwiftUI

struct DestinationWeatherSection: View {
    let weather: DestinationWeather

    var body: some View {
        Section {
            HStack(spacing: 16) {
                Image(systemName: weather.symbolName)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 44))
                    .frame(width: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(DestinationWeather.temperatureText(weather.temperature))
                        .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    Text(weather.condition.description)
                        .font(.subheadline)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Feels like \(DestinationWeather.temperatureText(weather.feelsLike))")
                    Text("Wind \(DestinationWeather.windText(weather.windSpeed))")
                    Text("Humidity \(weather.humidity)%")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)

            TimelineView(.everyMinute) { context in
                LabeledContent("Local time") {
                    Text(weather.localTime(at: context.date))
                }
            }

            ForEach(weather.days) { day in
                HStack {
                    Text(dayName(day.date, in: weather.timeZone))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: day.condition.symbolName())
                        .symbolRenderingMode(.multicolor)
                        .frame(width: 32)
                        .accessibilityLabel(day.condition.description)
                    Text("\(DestinationWeather.temperatureText(day.low)) – \(DestinationWeather.temperatureText(day.high))")
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
        } header: {
            Label("Weather in \(weather.placeName)", systemImage: "thermometer.medium")
        } footer: {
            Text("Weather data by Open-Meteo.com")
        }
    }

    /// "Today", then weekday names ("Thursday"), in the destination's time zone.
    private func dayName(_ date: Date, in timeZone: TimeZone) -> String {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        if calendar.isDate(date, inSameDayAs: Date()) {
            return "Today"
        }
        return date.formatted(Date.FormatStyle(timeZone: timeZone).weekday(.wide))
    }
}
