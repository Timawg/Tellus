import SwiftUI

struct CountryElectricityView: View {
    let countryCode: String
    let countryName: String
    let loadProfile: (String) async throws -> CountryElectricityProfile?

    @State private var result: Result<CountryElectricityProfile?, Error>?

    var body: some View {
        List {
            switch result {
            case .success(.some(let profile)):
                summary(profile)
                generationMix(profile)
            case .success(.none):
                ContentUnavailableView("No electricity data", systemImage: "bolt.slash",
                                       description: Text("Ember has no yearly electricity profile for this country."))
            case .failure:
                Section {
                    Text("Couldn't load electricity data.")
                        .foregroundStyle(.secondary)
                    Button("Retry") { result = nil }
                }
            case nil:
                ProgressView("Loading electricity data…")
                    .task {
                        do {
                            let profile = try await loadProfile(countryCode)
                            if !Task.isCancelled { result = .success(profile) }
                        } catch {
                            if !Task.isCancelled { result = .failure(error) }
                        }
                    }
            }

            Section {
                Link("Ember Yearly Electricity Data", destination: CountryElectricityProfile.sourceURL)
            } footer: {
                Text("Source: Ember, CC BY 4.0")
            }
        }
        .navigationTitle("Electricity profile")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func summary(_ profile: CountryElectricityProfile) -> some View {
        Section(countryName) {
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent("Domestic generation", value: terawattHours(profile.totalGenerationTWh))
                observation(year: profile.year)
            }
            if let netImports = profile.netImportsTWh {
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent(netImports < 0 ? "Net exports" : "Net imports",
                                   value: terawattHours(abs(netImports)))
                    observation(year: profile.year)
                }
            }
        }
    }

    private func generationMix(_ profile: CountryElectricityProfile) -> some View {
        Section("Generation by source") {
            if profile.fuels.isEmpty {
                Text(profile.totalGenerationTWh == 0
                     ? "Ember reports zero domestic generation for this year."
                     : "Ember has no breakdown by source for this year.")
                    .foregroundStyle(.secondary)
            }
            ForEach(profile.fuels) { fuel in
                VStack(alignment: .leading, spacing: 5) {
                    LabeledContent(fuel.name, value: terawattHours(fuel.generationTWh))
                    if let share = fuel.sharePercent {
                        ProgressView(value: min(share, 100), total: 100)
                            .tint(.cyan)
                            .accessibilityHidden(true)
                        Text("\((share / 100).formatted(.percent.precision(.fractionLength(0...3)))) of domestic generation")
                            .font(.subheadline)
                    }
                    observation(year: profile.year)
                }
            }
        }
    }

    private func observation(year: Int) -> some View {
        Text("Ember · \(String(year))")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func terawattHours(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...3)))) TWh"
    }
}
