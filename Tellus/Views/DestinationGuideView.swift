//
//  DestinationGuideView.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2026-11-04.
//

import SwiftUI

/// Everything a traveller should know about the selected country: key facts,
/// emergency numbers and neighbours, plus the Canadian government's entry,
/// health, laws and natural disaster advice, one topic at a time.
struct DestinationGuideView: View {

    let country: Country
    /// Nil while the advice is loading, or for places without advice.
    let guide: DestinationGuide?
    let isLoading: Bool
    let weather: DestinationWeather?
    let exchangeRates: [ExchangeRate]
    let neighbours: [Country]
    let selectCountry: (Country) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var topic: DestinationGuide.Topic = .overview

    var body: some View {
        NavigationStack {
            List {
                switch topic {
                case .overview:
                    overview
                default:
                    advice(for: topic)
                }
                if guide != nil {
                    sourceSection
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker("Topic", selection: $topic) {
                    ForEach(DestinationGuide.Topic.allCases) { topic in
                        Text(topic.title).tag(topic)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)
                // Solid, so the list doesn't show through as it scrolls underneath.
                .background(Color(uiColor: .systemGroupedBackground))
            }
            .navigationTitle(country.name?.common ?? "Destination")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(uiColor: .systemGroupedBackground))
        .preferredColorScheme(.dark)
    }

    // MARK: Overview

    @ViewBuilder
    private var overview: some View {
        if let weather {
            weatherSection(weather)
        }
        if !exchangeRates.isEmpty {
            moneySection
        }

        Section("At a glance") {
            if let capital = country.capital?.first {
                LabeledContent("Capital", value: capital)
            }
            if let region = country.subregion ?? country.region {
                LabeledContent("Region", value: region)
            }
            if !country.currencyDescriptions.isEmpty {
                LabeledContent(country.currencyDescriptions.count == 1 ? "Currency" : "Currencies",
                               value: country.currencyDescriptions.joined(separator: "\n"))
            }
            if !country.languageNames.isEmpty {
                LabeledContent(country.languageNames.count == 1 ? "Language" : "Languages",
                               value: country.languageNames.joined(separator: ", "))
            }
            if let callingCode = country.callingCode {
                LabeledContent("Calling code", value: callingCode)
            }
            if let domain = country.tld?.first {
                LabeledContent("Internet domain", value: domain)
            }
            if country.landlocked == true {
                LabeledContent("Coastline", value: "None, landlocked")
            }
        }
        .multilineTextAlignment(.trailing)

        emergencySection

        if !neighbours.isEmpty {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(neighbours) { neighbour in
                            Button {
                                selectCountry(neighbour)
                                dismiss()
                            } label: {
                                HStack(spacing: 8) {
                                    AsyncFlagView(flag: neighbour.flagURL)
                                        .frame(width: 28, height: 18)
                                    Text(neighbour.name?.common ?? "")
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(.white.opacity(0.1)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Shows this country on the map")
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            } header: {
                Text("Neighbours")
            } footer: {
                Text("Tap a country to go there.")
            }
        }
    }

    private func weatherSection(_ weather: DestinationWeather) -> some View {
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

    private var moneySection: some View {
        Section {
            ForEach(exchangeRates) { rate in
                LabeledContent("1 \(rate.home)", value: "\(ExchangeRate.format(rate.rate)) \(rate.destination)")
                LabeledContent("1 \(rate.destination)", value: "\(ExchangeRate.format(rate.inverse)) \(rate.home)")
            }
        } header: {
            Label("Exchange rate", systemImage: "banknote")
        } footer: {
            Text("From \(exchangeRates[0].home), the currency of your passport or region. Daily rates from currency-api, updated \(exchangeRates[0].date).")
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

    @ViewBuilder
    private var emergencySection: some View {
        if let guide, !guide.emergency.isEmpty {
            Section {
                blocks(guide.emergency)
            } header: {
                Label("Emergency numbers", systemImage: "phone.fill")
            } footer: {
                // Some places have no central number, only advice.
                if guide.emergency.contains(where: \.hasPhoneLink) {
                    Text("Tap a number to call it.")
                }
            }
        } else if guide == nil, isLoading {
            Section("Emergency numbers") {
                loadingRow
            }
        }
    }

    // MARK: Advice topics

    @ViewBuilder
    private func advice(for topic: DestinationGuide.Topic) -> some View {
        if let guide {
            let sections = guide.sections(for: topic)
            if sections.isEmpty {
                ContentUnavailableView("No \(topic.heading.lowercased()) advice",
                                       systemImage: "doc.text.magnifyingglass")
            } else {
                if let introduction = sections.first(where: { $0.title == nil }) {
                    Section(topic.heading) {
                        blocks(introduction.blocks)
                    }
                }
                Section(sections.first?.title == nil ? "Topics" : topic.heading) {
                    ForEach(sections.filter { $0.title != nil }) { section in
                        DisclosureGroup {
                            blocks(section.blocks)
                                .padding(.vertical, 4)
                        } label: {
                            Text(section.title ?? "")
                                .font(.body.weight(.semibold))
                        }
                    }
                }
                if topic == .entry {
                    Section {
                        Label("Visa rules for your passport are shown on the map card.", systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } else if isLoading {
            loadingRow
        } else {
            ContentUnavailableView("No travel advice",
                                   systemImage: "doc.text.magnifyingglass",
                                   description: Text("There's no travel advice for this destination."))
        }
    }

    private var sourceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Advice from the Government of Canada, adapted for all travellers. Updated \(guide?.updated ?? "").")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let url = guide?.adviceURL {
                    Link("Read the full advice on travel.gc.ca", destination: url)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.blue)
                }
            }
        }
    }

    // MARK: Pieces

    private var loadingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Loading advice…")
                .foregroundStyle(.secondary)
        }
    }

    private func blocks(_ blocks: [AdviceSection.Block]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let text):
                    Text(text)
                case .bullet(let text):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                        Text(text)
                    }
                    .padding(.leading, 4)
                case .subheading(let text):
                    Text(text)
                        .font(.subheadline.weight(.semibold))
                        .padding(.top, 4)
                }
            }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
