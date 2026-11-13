import Foundation

struct AnnualObservation: Decodable, Equatable, Identifiable, Sendable {
    let year: Int
    let value: Double

    var id: Int { year }
}

struct DemocracyProfile: Sendable {
    struct Series: Identifiable, Sendable {
        let id: String
        let area: String?
        let observations: [AnnualObservation]
    }

    let version: Int
    let series: [Series]
}

struct DemocracyDataset: Decodable, Sendable {
    let version: Int
    let countries: [String: [AnnualObservation]]

    func profile(countryCode: String?) -> DemocracyProfile {
        let code = countryCode?.uppercased()
        let series: [DemocracyProfile.Series]
        if code == "PSE" {
            // V-Dem reports these as distinct areas.
            series = [
                self.series(for: "PSE", area: "West Bank"),
                self.series(for: "PSG", area: "Gaza")
            ].compactMap { $0 }
        } else if let code, let countrySeries = self.series(for: code == "UNK" ? "XKX" : code) {
            series = [countrySeries]
        } else {
            series = []
        }
        return DemocracyProfile(version: version, series: series)
    }

    private func series(for code: String, area: String? = nil) -> DemocracyProfile.Series? {
        guard let observations = countries[code], !observations.isEmpty else { return nil }
        return .init(id: code, area: area, observations: observations)
    }
}

actor DemocracyDatasetStore {
    private let bundle: Bundle
    private var dataset: DemocracyDataset?

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func profile(countryCode: String?) throws -> DemocracyProfile {
        try Task.checkCancellation()
        if let dataset { return dataset.profile(countryCode: countryCode) }
        guard let url = bundle.url(forResource: "vdem-democracy", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let loaded = try JSONDecoder().decode(DemocracyDataset.self, from: Data(contentsOf: url))
        dataset = loaded
        return loaded.profile(countryCode: countryCode)
    }
}
