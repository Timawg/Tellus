import Foundation
import Observation
import Testing
@testable import Tellus

@MainActor
struct HazardLayerModelTests {
    @Test func previousActivationCannotPublishHazardsOrKeepPolling() async throws {
        let requested = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let release = AsyncStream<Void>.makeStream()
        let finished = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let network = StubNetwork { request in
            guard request.url?.lastPathComponent == "4.5_week.geojson" else {
                return Data(#"{"features":[]}"#.utf8)
            }
            requested.continuation.yield(())
            var iterator = release.stream.makeAsyncIterator()
            _ = await iterator.next()
            return Data(#"{"features":[{"id":"quake","properties":{"mag":5,"place":"Test quake","time":1000},"geometry":{"coordinates":[1,2,3]}}]}"#.utf8)
        }
        let preferences = MemoryPreferences(layers: [.hazards: true])
        let model = HazardLayerModel(service: HazardService(networkService: network), preferences: preferences)
        let previous = try #require(model.activationID)
        let refreshing = Task {
            await model.refreshWhileEnabled(for: previous)
            finished.continuation.yield(())
        }
        defer {
            refreshing.cancel()
            release.continuation.finish()
        }

        try await requireSignal(from: requested.stream, "The earthquake request should start")
        model.isEnabled = false
        model.isEnabled = true
        release.continuation.finish()

        try await requireSignal(from: finished.stream, "The previous activation should stop polling")
        let current = try #require(model.activationID)
        #expect(current != previous)
        #expect(model.hazards.isEmpty)

        let published = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        withObservationTracking {
            _ = model.hazards
        } onChange: {
            published.continuation.yield(())
        }
        let activeRefresh = Task { await model.refreshWhileEnabled(for: current) }
        defer { activeRefresh.cancel() }
        try await requireSignal(from: published.stream, "The current activation should publish hazards")
        #expect(model.hazards.map(\.id) == ["usgs-quake"])
        model.selectHazard(id: "usgs-quake")
        model.isEnabled = false
        #expect(model.hazards.isEmpty)
        #expect(model.selectedHazard == nil)
    }
}
