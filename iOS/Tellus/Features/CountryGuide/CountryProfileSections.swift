import SwiftUI

struct CountryProfileSections: View {
    let countryCode: String?
    let loadProfile: (String) async throws -> [CountryIndicatorObservation]

    @State private var result: Result<[CountryIndicatorObservation], Error>?

    var body: some View {
        switch result {
        case .success(let observations) where !observations.isEmpty:
            ForEach(CountryIndicator.Category.allCases, id: \.self) { category in
                let rows = observations.filter { $0.indicator.category == category }
                if !rows.isEmpty {
                    Section(category.rawValue) {
                        ForEach(rows) { row in
                            observationRow(row)
                        }
                    }
                }
            }
        case .success:
            Section("Country profile") {
                Text("No country indicators are available from the World Bank.")
                    .foregroundStyle(.secondary)
            }
        case .failure:
            Section("Country profile") {
                Text("Couldn't load country indicators.")
                    .foregroundStyle(.secondary)
                Button("Retry") { result = nil }
            }
        case nil:
            Section("Country profile") {
                ProgressView("Loading country indicators…")
                    .task {
                        do {
                            let observations = try await loadProfile(countryCode ?? "")
                            if !Task.isCancelled { result = .success(observations) }
                        } catch {
                            if !Task.isCancelled { result = .failure(error) }
                        }
                    }
            }
        }
    }

    private func observationRow(_ row: CountryIndicatorObservation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(row.indicator.title, value: formattedValue(row))
            if let countryCode,
               let source = URL(string: "https://data.worldbank.org/indicator/\(row.indicator.rawValue)?locations=\(countryCode)") {
                Link("World Bank · \(String(row.year))", destination: source)
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .accessibilityLabel("\(row.indicator.title), World Bank, observation year \(String(row.year))")
            }
        }
    }

    private func formattedValue(_ row: CountryIndicatorObservation) -> String {
        switch row.indicator {
        case .population:
            row.value.formatted(.number.precision(.fractionLength(0)))
        case .gdp:
            row.value.formatted(.number.notation(.compactName).precision(.significantDigits(3))) + " USD"
        case .gdpPerCapita:
            row.value.formatted(.currency(code: "USD").presentation(.isoCode).precision(.fractionLength(0)))
        case .surfaceArea:
            row.value.formatted(.number.precision(.fractionLength(0...1))) + " km²"
        case .internetUse, .electricityAccess:
            (row.value / 100).formatted(.percent.precision(.fractionLength(0...1)))
        }
    }
}
