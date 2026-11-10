import SwiftUI

struct CountryCostOfLivingView: View {
    let countryCode: String
    let countryName: String
    let loadPriceLevels: () async throws -> EurostatPriceLevels

    @State private var referenceCode = EurostatPriceLevels.euAverageCode
    @State private var result: Result<EurostatPriceLevels, Error>?

    var body: some View {
        List {
            switch result {
            case .success(let levels):
                if let comparison = levels.comparison(for: countryCode, against: referenceCode) {
                    comparisonSections(comparison, referenceAreas: levels.referenceAreas(for: countryCode))
                } else {
                    ContentUnavailableView("No comparable prices", systemImage: "basket",
                                           description: Text("Eurostat has no comparable household price data for this selection."))
                }
                Section {
                    Link("Eurostat price level data", destination: EurostatPriceLevels.sourceURL)
                } footer: {
                    Text("Eurostat data accessed \(levels.accessedAt, format: .dateTime.day().month(.abbreviated).year()).")
                }
            case .failure:
                Section {
                    Text("Couldn't load Eurostat prices.")
                        .foregroundStyle(.secondary)
                    Button("Retry") { result = nil }
                }
            case nil:
                ProgressView("Loading Eurostat prices…")
                    .task {
                        do {
                            let prices = try await loadPriceLevels()
                            if !Task.isCancelled { result = .success(prices) }
                        } catch {
                            if !Task.isCancelled { result = .failure(error) }
                        }
                    }
            }
        }
        .navigationTitle("Cost of living")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func comparisonSections(
        _ comparison: EurostatPriceLevels.Comparison,
        referenceAreas: [EurostatPriceLevels.Area]
    ) -> some View {
        let categories = EurostatPriceLevels.Category.allCases.filter { $0 != .overall }
        return Group {
            Section {
                Picker("Compare with", selection: $referenceCode) {
                    ForEach(referenceAreas) { area in
                        Text(area.name).tag(area.id)
                    }
                }
                .pickerStyle(.navigationLink)
                priceRow(.overall, comparison: comparison)
            } header: {
                Text(countryName)
            } footer: {
                Text("Eurostat · \(String(comparison.year)). National price levels for comparable goods and services.")
            }

            Section("Prices by category") {
                if categories.contains(where: { comparison.changes[$0] != nil }) {
                    ForEach(categories, id: \.self) { category in
                        priceRow(category, comparison: comparison)
                    }
                } else {
                    Text("Eurostat has no category breakdown for this comparison.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func priceRow(_ category: EurostatPriceLevels.Category, comparison: EurostatPriceLevels.Comparison) -> some View {
        LabeledContent(category.title) {
            if let change = comparison.changes[category] {
                Text(priceDifference(change))
                    .monospacedDigit()
            } else {
                Text("Unavailable")
            }
        }
    }

    private func priceDifference(_ change: Double) -> String {
        if abs(change) < 0.0005 { return "About the same" }
        let percent = abs(change).formatted(.percent.precision(.fractionLength(0...1)))
        return change > 0 ? "\(percent) higher" : "\(percent) lower"
    }
}
