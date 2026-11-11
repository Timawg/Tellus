import Foundation
import Testing
@testable import Tellus

final class MemoryPreferences: MapPreferencesStore {
    var nationality: Country?
    private var layers: [MapLayer: Bool]

    init(nationality: Country? = nil, layers: [MapLayer: Bool] = [:]) {
        self.nationality = nationality
        self.layers = layers
    }

    subscript(layer: MapLayer) -> Bool {
        get { layers[layer, default: false] }
        set { layers[layer] = newValue }
    }
}

struct StubNetwork: NetworkServiceProtocol {
    let respond: @Sendable (URLRequest) async throws -> Data

    func send(request: URLRequest) async throws -> Data {
        try await respond(request)
    }

    func send<T: Decodable>(request: URLRequest) async throws -> T {
        let data = try await send(request: request)
        return try JSONDecoder().decode(T.self, from: data)
    }
}

func testCountry(
    _ name: String,
    _ code: String,
    _ alpha3: String,
    currencies: [String] = []
) throws -> Country {
    let fixture: [String: Any] = [
        "name": ["common": name, "official": name, "native": [:]],
        "cca2": code,
        "cca3": alpha3,
        "latlng": [12, 34],
        "area": 12_100,
        "translations": [:],
        "currencies": Dictionary(uniqueKeysWithValues: currencies.map { ($0, ["name": $0]) }),
    ]
    return try JSONDecoder().decode(Country.self, from: JSONSerialization.data(withJSONObject: fixture))
}

func requireSignal(from stream: AsyncStream<Void>, _ comment: Comment) async throws {
    let signalled = await withTaskGroup(of: Bool.self) { group in
        group.addTask {
            var iterator = stream.makeAsyncIterator()
            return await iterator.next() != nil
        }
        group.addTask {
            try? await Task.sleep(for: .seconds(5))
            return false
        }
        defer { group.cancelAll() }
        return await group.next() ?? false
    }
    try #require(signalled, comment)
}
