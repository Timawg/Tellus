import Foundation
import os
import Testing
@testable import Tellus

@Suite
struct EurostatPriceTests {
    @Test func eurostatPriceComparisonUsesLatestSharedYearAndKeepsMissingCategories() async throws {
        let network = StubNetwork { request in
            #expect(request.url?.lastPathComponent == "prc_ppp_ind_1")
            let query = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
            #expect(query.contains(URLQueryItem(name: "indic_ppp", value: "PLI_EU27_2020")))
            let categories = Set(query.filter { $0.name == "ppp_cat18" }.compactMap(\.value))
            #expect(categories == ["E011", "A0101", "A0104", "A0107", "A0111"])
            return Self.eurostatDataset
        }

        let prices = try await EurostatPriceService(networkService: network).getPriceLevels()
        let greece = try #require(prices.comparison(for: "GR", against: "SE"))
        #expect(greece.year == 2024)
        let greeceOverall = try #require(greece.changes[.overall])
        let greeceGroceries = try #require(greece.changes[.groceries])
        #expect(abs(greeceOverall + 0.25) <= 0.0001)
        #expect(abs(greeceGroceries - 0.10) <= 0.0001)
        #expect(greece.changes[.transport] == nil)
        #expect(prices.referenceAreas(for: "GR").map(\.id) == ["EU27_2020", "SE"])

        let sweden = try #require(prices.comparison(for: "SE", against: EurostatPriceLevels.euAverageCode))
        #expect(sweden.year == 2025)
        let swedenOverall = try #require(sweden.changes[.overall])
        #expect(abs(swedenOverall - 0.21) <= 0.0001)
        #expect(prices.comparison(for: "GB", against: EurostatPriceLevels.euAverageCode)?.year == 2025)
        #expect(prices.comparison(for: "CA", against: EurostatPriceLevels.euAverageCode) == nil)
    }

    @Test func eurostatRefreshSurvivesCancellationAndKeepsLastSuccessfulSnapshot() async throws {
        let requested = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let release = AsyncStream<Void>.makeStream()
        let network = EurostatNetwork { requestNumber in
            switch requestNumber {
            case 1:
                requested.continuation.yield(())
                var iterator = release.stream.makeAsyncIterator()
                _ = await iterator.next()
            case 2:
                throw URLError(.notConnectedToInternet)
            default:
                break
            }
            return Self.eurostatDataset
        }
        let firstAccess = Date(timeIntervalSince1970: 1_800_000_000)
        let now = OSAllocatedUnfairLock(initialState: firstAccess)
        let service = EurostatPriceService(networkService: network, now: { now.withLock { $0 } })

        let cancelled = Task { try await service.getPriceLevels() }
        defer { release.continuation.finish() }
        try await requireSignal(from: requested.stream, "The first Eurostat refresh should start")
        let remaining = Task { try await service.getPriceLevels() }
        cancelled.cancel()
        release.continuation.finish()

        await #expect(throws: CancellationError.self) { try await cancelled.value }
        let initial = try await remaining.value
        #expect(!initial.isStale)
        #expect(initial.accessedAt == firstAccess)
        #expect(await network.requestCount == 1)

        let nextDay = firstAccess.addingTimeInterval(24 * 60 * 60)
        now.withLock { $0 = nextDay }
        let stale = try await service.getPriceLevels()
        #expect(stale.isStale)
        #expect(stale.accessedAt == firstAccess)
        #expect(stale.comparison(for: "SE", against: EurostatPriceLevels.euAverageCode)?.year == 2025)

        let recovered = try await service.getPriceLevels()
        #expect(!recovered.isStale)
        #expect(recovered.accessedAt == nextDay)
        #expect(await network.requestCount == 3)
    }

    private static let eurostatDataset = Data("""
        {
          "id": ["freq", "indic_ppp", "ppp_cat18", "geo", "time"],
          "size": [1, 1, 3, 4, 3],
          "dimension": {
            "freq": {"category": {"index": {"A": 0}}},
            "indic_ppp": {"category": {"index": {"PLI_EU27_2020": 0}}},
            "ppp_cat18": {"category": {"index": {"A0101": 0, "A0107": 1, "E011": 2}}},
            "geo": {"category": {"index": {"EU27_2020": 0, "SE": 1, "EL": 2, "UK": 3},
                                 "label": {"SE": "Sweden", "EL": "Greece", "UK": "United Kingdom"}}},
            "time": {"category": {"index": {"2023": 0, "2024": 1, "2025": 2}}}
          },
          "value": {"4": 100, "7": 110, "16": 120, "18": 100,
                    "24": 100, "25": 100, "26": 100, "28": 120, "29": 121,
                    "30": 85, "31": 90, "35": 123}
        }
        """.utf8)
}

private actor EurostatNetwork: NetworkServiceProtocol {
    private let respond: @Sendable (Int) async throws -> Data
    private(set) var requestCount = 0

    init(respond: @escaping @Sendable (Int) async throws -> Data) {
        self.respond = respond
    }

    func send(request: URLRequest) async throws -> Data {
        requestCount += 1
        return try await respond(requestCount)
    }

    nonisolated func send<T: Decodable>(request: URLRequest) async throws -> T {
        try JSONDecoder().decode(T.self, from: await send(request: request))
    }
}
