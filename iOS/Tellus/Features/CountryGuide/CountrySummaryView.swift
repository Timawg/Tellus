import SwiftUI

struct CountrySummaryView: View {
    let country: Country?
    let passport: Country?
    let model: CountryGuideModel
    let neighbours: (Country) -> [Country]
    let selectCountry: (Country) -> Void
    @State private var guideTopic: DestinationGuide.Topic?

    @ViewBuilder
    var body: some View {
        if let country, let name = country.name?.common, let flag = country.flagURL {
            VStack(spacing: 10) {
                VStack(spacing: 2) {
                    HStack(alignment: .center, spacing: 8) {
                        AsyncFlagView(flag: flag)
                        Text(name)
                            .font(.headline)
                    }
                    // City-states such as Singapore would repeat their name.
                    if let capital = country.capital?.first, capital != name {
                        Text(capital)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .accessibilityLabel("Capital: \(capital)")
                    }
                }
                liveInfoStrip
                alertBanner
                countryGuideButton
            }
            .sheet(item: $guideTopic) { topic in
                DestinationGuideView(
                    country: country,
                    model: model,
                    initialTopic: topic,
                    passport: passport,
                    neighbours: neighbours(country),
                    selectCountry: selectCountry
                )
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .floatingGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .environment(\.colorScheme, .dark)
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }

    /// Opens the country guide. Small dots above it show the travel advisory,
    /// visa, disease outbreak and natural disaster statuses, which the
    /// guide explains.
    private var countryGuideButton: some View {
        Button {
            guideTopic = .overview
        } label: {
            Label("Country guide", systemImage: "book.closed")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(.white.opacity(0.15)))
                .overlay(alignment: .topTrailing) {
                    statusDots
                        .offset(x: 6, y: -6)
                }
        }
        .buttonStyle(.plain)
        .accessibilityValue(statusSummary)
        .animation(.easeInOut, value: travelStatuses.map(\.value))
    }

    /// Advisory, visa, health and disaster statuses for the selected country,
    /// in the order the dots show them.
    private var travelStatuses: [TravelStatus] {
        model.travelStatuses(passport: passport)
    }

    /// The statuses' colours as small dots in a dark pill.
    @ViewBuilder
    private var statusDots: some View {
        let statuses = travelStatuses
        if !statuses.isEmpty {
            HStack(spacing: 3) {
                ForEach(statuses) { status in
                    CircularStatusView(colors: status.colors)
                        .frame(width: 10, height: 10)
                }
            }
            .padding(3)
            .background(Capsule().fill(.black.opacity(0.55)))
            .transition(.scale.combined(with: .opacity))
            .accessibilityHidden(true)
        }
    }

    /// "Travel advisory: Exercise normal security precautions. Visa: …" for
    /// VoiceOver.
    private var statusSummary: String {
        travelStatuses
            .map { "\($0.title): \($0.value)" }
            .joined(separator: ". ")
    }

    /// One banner for the most pressing thing happening in the country: an
    /// active disaster, an ongoing internet disruption, or a WHO outbreak
    /// report from the last 30 days. Tapping it opens the guide, which lists
    /// them all.
    private var cardAlert: (title: String, symbol: String, color: Color, accessibility: String, topic: DestinationGuide.Topic)? {
        if let alert = model.disasterAlerts.first(where: \.isUrgent) {
            return (alert.name, alert.kind.symbolName, alert.level == .red ? .red : .orange, "\(alert.level.rawValue) alert: \(alert.name)", .climate)
        }
        if model.internetOutages.contains(where: \.isOngoing) {
            return ("Internet disruption detected", "wifi.exclamationmark", .purple, "Internet disruption detected", .overview)
        }
        if let report = model.outbreakReports.first,
           report.published > Date().addingTimeInterval(-30 * 24 * 60 * 60) {
            return ("Outbreak: \(report.disease)", "cross.case.fill", .orange, "Recent outbreak report: \(report.disease)", .health)
        }
        return nil
    }

    @ViewBuilder
    private var alertBanner: some View {
        if let alert = cardAlert {
            Button {
                guideTopic = alert.topic
            } label: {
                Label(alert.title, systemImage: alert.symbol)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(alert.color.opacity(0.85)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(alert.accessibility)
            .accessibilityHint("Opens the country guide")
            .transition(.opacity)
        }
    }

    /// Weather and local time at the capital, and the exchange rate from the
    /// home currency, in one line under the country name.
    @ViewBuilder
    private var liveInfoStrip: some View {
        let weather = model.destinationWeather
        let rate = model.exchangeRates.first
        if weather != nil || rate != nil {
            HStack(spacing: 14) {
                if let weather {
                    Label {
                        Text(DestinationWeather.temperatureText(weather.temperature))
                    } icon: {
                        Image(systemName: weather.symbolName)
                            .symbolRenderingMode(.multicolor)
                    }
                    .accessibilityLabel("\(weather.condition.description), \(DestinationWeather.temperatureText(weather.temperature))")
                    TimelineView(.everyMinute) { context in
                        Label {
                            Text(weather.localTime(at: context.date))
                        } icon: {
                            Image(systemName: "clock")
                        }
                        .accessibilityLabel("Local time")
                        .accessibilityValue(Text(weather.localTime(at: context.date)))
                    }
                }
                if let rate {
                    Label("1 \(rate.home) = \(ExchangeRate.format(rate.rate)) \(rate.destination)", systemImage: "banknote")
                }
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(.white.opacity(0.9))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .transition(.opacity)
        }
    }
}
