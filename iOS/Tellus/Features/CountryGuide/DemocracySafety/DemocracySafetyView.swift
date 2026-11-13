import Charts
import SwiftUI

struct DemocracySafetyView: View {
    let country: Country
    let model: CountryGuideModel

    var body: some View {
        List {
            DemocracySection {
                try await model.loadDemocracyProfile(countryCode: country.cca3)
            }

            HomicideSection {
                guard let code = country.cca2 else { return [] }
                return try await model.loadHomicideTrend(countryCode: code)
            }
        }
        .id(country.id)
        .navigationTitle("Democracy & Safety")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DemocracySection: View {
    let load: () async throws -> DemocracyProfile
    @State private var result: Result<DemocracyProfile, Error>?

    var body: some View {
        Section {
            switch result {
            case .success(let profile) where !profile.series.isEmpty:
                ForEach(profile.series) { series in
                    if let latest = series.observations.last {
                        LabeledContent(series.area ?? "Electoral Democracy Index") {
                            Text("\(latest.value, format: .number.precision(.fractionLength(3))) / 1")
                                .monospacedDigit()
                        }
                        Text("Observation year \(String(latest.year))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        AnnualObservationChart(
                            observations: series.observations,
                            metric: "Electoral Democracy Index",
                            upperBound: 1
                        )
                    }
                }
            case .success:
                Text("V-Dem has no observations for this destination in the bundled release.")
                    .foregroundStyle(.secondary)
            case .failure:
                Text("Couldn’t load the bundled V-Dem data.")
                    .foregroundStyle(.secondary)
            case nil:
                ProgressView("Loading democracy data…")
                    .task {
                        do {
                            let profile = try await load()
                            if !Task.isCancelled { result = .success(profile) }
                        } catch {
                            if !Task.isCancelled { result = .failure(error) }
                        }
                    }
            }
        } header: {
            Text("Democracy")
        } footer: {
            ProfileSectionFooter {
                Text("V-Dem’s index covers election quality, voting rights, and freedom of expression and association.")
                if case .success(let profile) = result {
                    GuideSourceLink(
                        "V-Dem Country-Year Dataset v\(String(profile.version))",
                        destination: Self.datasetURL
                    )
                    Text("Adapted from the full dataset using the ten most recent years.")
                    GuideSourceLink("CC BY-SA 4.0", destination: Self.licenseURL)
                }
            }
        }
    }

    private static let datasetURL = URL(string: "https://v-dem.net/data/dataset-archive/")!
    private static let licenseURL = URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")!
}

private struct HomicideSection: View {
    let load: () async throws -> [AnnualObservation]
    @State private var result: Result<[AnnualObservation], Error>?

    var body: some View {
        Section {
            switch result {
            case .success(let observations):
                if let latest = observations.last {
                    LabeledContent("Intentional homicides per 100,000 people") {
                        Text(latest.value, format: .number.precision(.fractionLength(2)))
                            .monospacedDigit()
                    }
                    Text("Observation year \(String(latest.year))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    AnnualObservationChart(
                        observations: observations,
                        metric: "Intentional homicides per 100,000 people",
                        upperBound: max(1, (observations.map(\.value).max() ?? 0).rounded(.up))
                    )
                } else {
                    Text("No homicide observations are available for this destination.")
                        .foregroundStyle(.secondary)
                }
            case .failure:
                Text("Couldn’t load homicide statistics.")
                    .foregroundStyle(.secondary)
                Button("Retry") { result = nil }
            case nil:
                ProgressView("Loading homicide statistics…")
                    .task {
                        do {
                            let observations = try await load()
                            if !Task.isCancelled { result = .success(observations) }
                        } catch {
                            if !Task.isCancelled { result = .failure(error) }
                        }
                    }
            }
        } header: {
            Text("Public safety")
        } footer: {
            ProfileSectionFooter {
                Text("Up to ten years of reported data.")
                GuideSourceLink("UNODC via World Bank World Development Indicators", destination: Self.indicatorURL)
                GuideSourceLink("CC BY 4.0", destination: Self.licenseURL)
            }
        }
    }

    private static let indicatorURL = URL(string: "https://data.worldbank.org/indicator/VC.IHR.PSRC.P5")!
    private static let licenseURL = URL(string: "https://creativecommons.org/licenses/by/4.0/")!
}

private struct AnnualObservationChart: View {
    let observations: [AnnualObservation]
    let metric: String
    let upperBound: Double

    var body: some View {
        if let firstYear = observations.first?.year, let lastYear = observations.last?.year, firstYear < lastYear {
            let years = firstYear...lastYear
            Chart(observations) { observation in
                PointMark(
                    x: .value("Year", observation.year),
                    y: .value(metric, observation.value)
                )
                .accessibilityLabel(String(observation.year))
            }
            // Limit the numeric scale to the reported years while keeping gaps proportional to time.
            .chartXScale(domain: years, range: .plotDimension(padding: 20))
            .chartYScale(domain: 0...upperBound)
            .chartXAxis {
                AxisMarks(preset: .aligned, values: axisYears(in: years)) { axis in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(centered: false, anchor: .top) {
                        if let year = axis.as(Int.self) { Text(String(year)) }
                    }
                }
            }
            .frame(height: 150)
        }
    }

    private func axisYears(in years: ClosedRange<Int>) -> [Int] {
        let first = years.lowerBound
        let last = years.upperBound
        let middle = first + (last - first) / 2
        return first < middle ? [first, middle, last] : [first, last]
    }
}

private struct ProfileSectionFooter<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .font(.footnote)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Democracy and safety") {
    List {
        DemocracySection {
            DemocracyProfile(version: 16, series: [
                .init(id: "sample", area: nil, observations: [
                    .init(year: 2023, value: 0.73),
                    .init(year: 2024, value: 0.78),
                    .init(year: 2025, value: 0.80)
                ])
            ])
        }
        HomicideSection {
            [.init(year: 2021, value: 2.1), .init(year: 2023, value: 1.7)]
        }
    }
    .preferredColorScheme(.dark)
}
