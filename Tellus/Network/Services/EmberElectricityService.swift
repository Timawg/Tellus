import Foundation

struct CountryElectricityProfile: Codable, Equatable {
    struct Fuel: Codable, Equatable, Identifiable {
        let name: String
        let generationTWh: Double
        let sharePercent: Double?

        var id: String { name }
    }

    let year: Int
    let totalGenerationTWh: Double
    let netImportsTWh: Double?
    let fuels: [Fuel]

    static let sourceURL = URL(string: "https://ember-energy.org/data/yearly-electricity-data/")!
}

protocol EmberElectricityServiceProtocol: Service {
    func getProfile(countryCode: String) async throws -> CountryElectricityProfile?
}

actor EmberElectricityService: EmberElectricityServiceProtocol {
    nonisolated let rootURL = "https://files.ember-energy.org/public-downloads/generation/outputs"
    private let networkService: NetworkServiceProtocol
    private let requestFactory: URLRequestFactory
    private let cacheURL: URL?
    private var snapshot: Snapshot?
    private var refreshTask: Task<Snapshot, Error>?

    private struct Snapshot: Codable {
        let fetchedAt: Date
        let profiles: [String: CountryElectricityProfile]
    }

    private struct YearlyDataset: Endpoint {
        let path = "/release_generation_yearly_global.csv"
        let httpMethod: HTTPMethod = .get
    }

    init(networkService: NetworkServiceProtocol, requestFactory: URLRequestFactory = .default) {
        self.init(
            networkService: networkService,
            requestFactory: requestFactory,
            cacheURL: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
                .appendingPathComponent("ember-electricity-v1.json")
        )
    }

    init(networkService: NetworkServiceProtocol, requestFactory: URLRequestFactory = .default, cacheURL: URL?) {
        self.networkService = networkService
        self.requestFactory = requestFactory
        self.cacheURL = cacheURL
    }

    func getProfile(countryCode: String) async throws -> CountryElectricityProfile? {
        let input = countryCode.uppercased()
        guard input.count == 3, input.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        // Tellus's country dataset uses UNK for Kosovo. Ember uses XKX.
        let code = input == "UNK" ? "XKX" : input
        if let refreshTask {
            return try await refreshTask.value.profiles[code]
        }
        if snapshot == nil, let cacheURL, let data = try? Data(contentsOf: cacheURL) {
            snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
        }
        if let snapshot, Date().timeIntervalSince(snapshot.fetchedAt) < 7 * 24 * 60 * 60 {
            return snapshot.profiles[code]
        }

        // One global download serves every country. A view disappearing does
        // not cancel the refresh for other callers or discard the new cache.
        let task = Task { try await refresh() }
        refreshTask = task
        return try await task.value.profiles[code]
    }

    private func refresh() async throws -> Snapshot {
        defer { refreshTask = nil }
        do {
            let request = try requestFactory.createURLRequest(root: rootURL, endpoint: YearlyDataset())
            let data: Data = try await networkService.send(request: request)
            let profiles = try EmberElectricityDataset.profiles(from: data)
            let fresh = Snapshot(fetchedAt: Date(), profiles: profiles)
            snapshot = fresh
            if let cacheURL, let encoded = try? JSONEncoder().encode(fresh) {
                try? encoded.write(to: cacheURL, options: .atomic)
            }
            return fresh
        } catch {
            if let snapshot { return snapshot }
            throw error
        }
    }
}

enum EmberElectricityDataset {
    private struct Observations {
        var total: Double?
        var imports: Double?
        var fuels: [CountryElectricityProfile.Fuel] = []
    }

    static func profiles(from data: Data) throws -> [String: CountryElectricityProfile] {
        guard let contents = String(data: data, encoding: .utf8) else { throw HTTPError.invalidResponse }
        let lines = contents.split(whereSeparator: \.isNewline)
        guard let first = lines.first else { throw HTTPError.invalidResponse }
        let header = fields(in: first).map { value($0).trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}")) }
        guard let codeColumn = header.firstIndex(of: "ISO 3 code"),
              let yearColumn = header.firstIndex(of: "Year"),
              let sourceColumn = header.firstIndex(of: "Electricity source"),
              let aggregateColumn = header.firstIndex(of: "Is aggregated source"),
              let generationColumn = header.firstIndex(of: "Generation (TWh)"),
              let shareColumn = header.firstIndex(of: "Share of generation (%)") else {
            throw HTTPError.invalidResponse
        }

        var observations: [String: [Int: Observations]] = [:]
        for line in lines.dropFirst() {
            let row = fields(in: line)
            guard row.count == header.count, row[codeColumn].utf8.count == 3,
                  let year = Int(row[yearColumn]),
                  let generation = Double(row[generationColumn]), generation.isFinite else { continue }
            let source = value(row[sourceColumn])
            let code = String(row[codeColumn])
            switch source {
            case "Total generation" where generation >= 0:
                observations[code, default: [:]][year, default: Observations()].total = generation
            case "Net imports":
                observations[code, default: [:]][year, default: Observations()].imports = generation
            case _ where row[aggregateColumn] == "False" && generation > 0 && !source.isEmpty:
                let share = Double(row[shareColumn]).flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
                let fuel = CountryElectricityProfile.Fuel(name: source, generationTWh: generation, sharePercent: share)
                observations[code, default: [:]][year, default: Observations()].fuels.append(fuel)
            default:
                continue
            }
        }

        let profiles = observations.compactMapValues { years -> CountryElectricityProfile? in
            guard let (year, latest) = years.filter({ $0.value.total != nil }).max(by: { $0.key < $1.key }),
                  let total = latest.total else { return nil }
            return CountryElectricityProfile(
                year: year,
                totalGenerationTWh: total,
                netImportsTWh: latest.imports,
                fuels: latest.fuels.sorted { $0.generationTWh > $1.generationTWh }
            )
        }
        guard !profiles.isEmpty else { throw HTTPError.invalidResponse }
        return profiles
    }

    private static func fields(in row: Substring) -> [Substring] {
        guard row.contains("\"") else { return row.split(separator: ",", omittingEmptySubsequences: false) }
        var fields: [Substring] = []
        var start = row.startIndex
        var quoted = false
        for index in row.indices {
            switch row[index] {
            case "\"": quoted.toggle()
            case "," where !quoted:
                fields.append(row[start..<index])
                start = row.index(after: index)
            default: break
            }
        }
        fields.append(row[start...])
        return fields
    }

    private static func value(_ field: Substring) -> String {
        guard field.first == "\"", field.last == "\"", field.count >= 2 else { return String(field) }
        return field.dropFirst().dropLast().replacingOccurrences(of: "\"\"", with: "\"")
    }
}
