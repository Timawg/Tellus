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
    let model: CountryGuideModel
    /// The tab shown when the guide opens.
    var initialTopic: DestinationGuide.Topic = .overview
    /// The passport the visa status is for.
    let passport: Country?
    let neighbours: [Country]
    let selectCountry: (Country) -> Void

    @Environment(\.dismiss) private var dismiss
    /// Nil until a tab is picked, so the guide opens on `initialTopic`.
    @State private var selectedTopic: DestinationGuide.Topic?

    private var topic: DestinationGuide.Topic { selectedTopic ?? initialTopic }

    private var statuses: [TravelStatus] { model.travelStatuses(passport: passport) }

    var body: some View {
        NavigationStack {
            List {
                switch topic {
                case .overview:
                    overview
                case .entry:
                    statusSection(for: [.visa])
                case .health:
                    statusSection(for: [.health])
                    if !model.outbreakReports.isEmpty {
                        outbreaksSection
                    }
                case .climate:
                    statusSection(for: [.disasters])
                    if !model.disasterAlerts.isEmpty {
                        alertsSection
                    }
                case .laws:
                    EmptyView()
                }
                if topic != .overview {
                    TravelAdviceSection(
                        topic: topic,
                        guide: model.destinationGuide,
                        advisoryStatus: model.advisoryStatus,
                        isLoading: model.isLoadingDestinationGuide,
                        loadFailed: model.advisoryLoadFailed
                    )
                }
                if let guide = model.destinationGuide {
                    GuideAdviceSource(guide: guide)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker("Topic", selection: Binding(get: { topic }, set: { selectedTopic = $0 })) {
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
}

private extension DestinationGuideView {
    // MARK: Overview

    @ViewBuilder
    var overview: some View {
        statusOverviewSection
        Section {
            NavigationLink {
                DemocracySafetyView(country: country, model: model)
            } label: {
                Label("Democracy & Safety", systemImage: "building.columns")
            }
        }
        CountryProfileSections(countryCode: country.cca2, loadProfile: model.loadCountryProfile(countryCode:))
            .id(country.cca2)
        if let code = country.cca2 {
            Section("Prices") {
                NavigationLink {
                    CountryCostOfLivingView(countryCode: code, countryName: country.name?.common ?? code,
                                            loadPriceLevels: model.loadPriceLevels)
                } label: {
                    Label("Cost of living", systemImage: "basket")
                }
            }
        }
        if let code = country.cca3 {
            Section("Energy") {
                NavigationLink {
                    CountryElectricityView(
                        countryCode: code,
                        countryName: country.name?.common ?? code,
                        loadProfile: model.loadElectricityProfile(countryCode:)
                    )
                } label: {
                    Label("Electricity profile", systemImage: "bolt")
                }
            }
        }
        if let recentEvents = model.recentEvents, !recentEvents.events.isEmpty {
            RecentEventsSection(recentEvents: recentEvents)
        }
        if !model.internetOutages.isEmpty {
            outagesSection
        }
        if let weather = model.destinationWeather {
            DestinationWeatherSection(weather: weather)
        }
        if !model.exchangeRates.isEmpty {
            moneySection(model.exchangeRates)
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
                                    AsyncFlagView(flag: neighbour.flagURL, size: CGSize(width: 28, height: 18))
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

    func moneySection(_ exchangeRates: [ExchangeRate]) -> some View {
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

    var outagesSection: some View {
        Section {
            ForEach(model.internetOutages) { outage in
                VStack(alignment: .leading, spacing: 6) {
                    Label {
                        Text(outage.isOngoing ? "Internet disruption detected" : "Recent internet disruption")
                            .font(.body.weight(.semibold))
                    } icon: {
                        Image(systemName: "wifi.exclamationmark")
                            .foregroundStyle(outage.isOngoing ? .purple : .secondary)
                    }
                    Text(outage.isOngoing
                         ? "Since \(outage.start.formatted(date: .abbreviated, time: .shortened))"
                         : "\(outage.start.formatted(date: .abbreviated, time: .shortened)) – \(outage.end.formatted(date: .omitted, time: .shortened))")
                        .font(.subheadline)
                    Text("Seen in: \(outage.signals.joined(separator: ", "))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
            }
        } header: {
            Label("Connectivity", systemImage: "network")
        } footer: {
            Text("Outages in the last 7 days seen by at least two independent signals, from IODA (Georgia Tech). A drop can mean a shutdown, a power cut or a cable fault.")
        }
    }

    var outbreaksSection: some View {
        Section {
            ForEach(model.outbreakReports.prefix(5)) { report in
                VStack(alignment: .leading, spacing: 4) {
                    Text(report.published, format: .dateTime.day().month(.abbreviated).year())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(report.disease)
                        .font(.body.weight(.semibold))
                    if !report.summary.isEmpty {
                        Text(report.summary)
                            .font(.subheadline)
                    }
                    if let url = report.url {
                        Link("Read the WHO report", destination: url)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.blue)
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Label("Outbreak news", systemImage: "cross.case.fill")
        } footer: {
            Text("WHO Disease Outbreak News reports naming this country, the latest per disease.")
        }
    }

    var alertsSection: some View {
        Section {
            ForEach(model.disasterAlerts) { alert in
                VStack(alignment: .leading, spacing: 6) {
                    Label {
                        Text(alert.name)
                            .font(.body.weight(.semibold))
                    } icon: {
                        Image(systemName: alert.kind.symbolName)
                            .foregroundStyle(alert.level == .red ? .red : .orange)
                    }
                    if let severity = alert.severity {
                        Text(severity)
                            .font(.subheadline)
                    }
                    HStack {
                        Text("\(alert.level.rawValue) alert")
                            .foregroundStyle(alert.level == .red ? .red : .orange)
                        if let start = alert.start {
                            Text("since \(start.formatted(date: .abbreviated, time: .omitted))")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let url = alert.reportURL {
                            Link("Report", destination: url)
                                .foregroundStyle(.blue)
                        }
                    }
                    .font(.footnote)
                }
                .padding(.vertical, 2)
            }
        } header: {
            Label("Active alerts", systemImage: "exclamationmark.triangle.fill")
        } footer: {
            Text("Disaster alerts from GDACS, the Global Disaster Alert and Coordination System.")
        }
    }

    @ViewBuilder
    var emergencySection: some View {
        if let guide = model.destinationGuide, !guide.emergency.isEmpty {
            Section {
                AdviceBlocks(blocks: guide.emergency)
            } header: {
                Label("Emergency numbers", systemImage: "phone.fill")
            } footer: {
                // Some places have no central number, only advice.
                if guide.emergency.contains(where: \.hasPhoneLink) {
                    Text("Tap a number to call it.")
                }
            }
        } else if model.isLoadingDestinationGuide {
            Section("Emergency numbers") {
                AdviceLoadingRow()
            }
        }
    }

    // MARK: Statuses

    /// Every status, each opening the tab that explains it. These are the
    /// dots on the map card's guide button.
    @ViewBuilder
    var statusOverviewSection: some View {
        if !statuses.isEmpty {
            Section("Status") {
                ForEach(statuses) { status in
                    Button {
                        withAnimation { selectedTopic = status.kind.topic }
                    } label: {
                        HStack {
                            TravelStatusRow(status: status)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .tint(.primary)
                    .accessibilityHint("Shows \(status.kind.topic.title)")
                }
            }
        }
    }

    /// The statuses a tab is about, at the top of that tab.
    @ViewBuilder
    func statusSection(for kinds: [TravelStatus.Kind]) -> some View {
        let shown = statuses.filter { kinds.contains($0.kind) }
        if !shown.isEmpty || kinds.contains(.visa) {
            Section {
                ForEach(shown) { status in
                    TravelStatusRow(status: status)
                }
            } header: {
                Text("Status")
            } footer: {
                if kinds.contains(.visa), model.admissoryStatus == nil {
                    Text("Choose your passport on the map to see visa rules.")
                }
            }
        }
    }
}
