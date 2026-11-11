import Foundation
import Testing
@testable import Tellus

@MainActor
struct CableLayerModelTests {
    @Test func previousActivationCannotPublishCableRoutes() async throws {
        let requested = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let release = AsyncStream<Void>.makeStream()
        let network = StubNetwork { request in
            switch request.url?.lastPathComponent {
            case "cable-geo.json":
                requested.continuation.yield(())
                var iterator = release.stream.makeAsyncIterator()
                _ = await iterator.next()
                return Data(#"{"features":[{"properties":{"id":"cable","name":"Test cable"},"geometry":{"coordinates":[[[0,0],[1,1]]]}}]}"#.utf8)
            case "landing-point-geo.json":
                return Data(#"{"features":[]}"#.utf8)
            default:
                throw URLError(.unsupportedURL)
            }
        }
        let preferences = MemoryPreferences(layers: [.cables: true])
        let model = CableLayerModel(service: CableService(networkService: network), preferences: preferences)
        let previous = try #require(model.activationID)
        let loading = Task { await model.load(for: previous) }
        defer {
            loading.cancel()
            release.continuation.finish()
        }

        try await requireSignal(from: requested.stream, "The cable request should start")
        model.isEnabled = false
        model.isEnabled = true
        let current = try #require(model.activationID)
        release.continuation.finish()
        await loading.value

        #expect(previous != current)
        #expect(model.cables.isEmpty)
        await model.load(for: current)
        #expect(model.cables.map(\.id) == ["cable"])
        model.selectCable("cable")
        model.isEnabled = false
        #expect(!preferences[.cables])
        #expect(model.selectedCable == nil)
        #expect(model.cables.isEmpty)
    }
}
