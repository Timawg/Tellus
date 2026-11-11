import Foundation

@MainActor
@Observable
final class HazardLayerModel {
    private let service: HazardServiceProtocol
    private let preferences: MapPreferencesStore
    private(set) var activationID: UUID?
    private(set) var hazards: [NaturalHazard] = []
    private(set) var tracks: [CycloneTrack] = []
    // Keep the open sheet's snapshot when the underlying feed refreshes.
    var selectedHazard: NaturalHazard?

    var isEnabled: Bool {
        get { activationID != nil }
        set {
            guard isEnabled != newValue else { return }
            activationID = newValue ? UUID() : nil
            preferences[.hazards] = newValue
            if !newValue {
                selectedHazard = nil
                hazards = []
                tracks = []
            }
        }
    }

    init(service: HazardServiceProtocol, preferences: MapPreferencesStore) {
        self.service = service
        self.preferences = preferences
        activationID = preferences[.hazards] ? UUID() : nil
    }

    func selectHazard(id: String) {
        selectedHazard = hazards.first { $0.id == id }
    }

    func refreshWhileEnabled(for activation: UUID?) async {
        guard let activation else { return }
        while activationID == activation, !Task.isCancelled {
            await refresh(for: activation)
            guard activationID == activation, !Task.isCancelled else { return }
            do {
                try await Task.sleep(for: .seconds(15 * 60))
            } catch {
                return
            }
        }
    }

    private func refresh(for activation: UUID) async {
        guard let loaded = try? await service.getHazards(),
              activationID == activation, !Task.isCancelled else { return }
        if loaded != hazards { hazards = loaded }

        var newTracks: [CycloneTrack] = []
        for cyclone in loaded where cyclone.kind == .cyclone {
            let track = try? await service.getTrack(for: cyclone)
            guard activationID == activation, !Task.isCancelled else { return }
            if let track { newTracks.append(track) }
        }
        if newTracks != tracks { tracks = newTracks }
    }
}
