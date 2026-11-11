import Foundation

@MainActor
@Observable
final class CableLayerModel {
    private let service: CableServiceProtocol
    private let preferences: MapPreferencesStore
    private var dataset: (cables: [SubmarineCable], landingPoints: [CableLandingPoint])?
    private(set) var activationID: UUID?
    private(set) var selectedCableID: String?
    private(set) var selectedCableDetails: CableDetails?

    var isEnabled: Bool {
        get { activationID != nil }
        set {
            guard isEnabled != newValue else { return }
            activationID = newValue ? UUID() : nil
            preferences[.cables] = newValue
            if !newValue { selectCable(nil) }
        }
    }

    var cables: [SubmarineCable] { isEnabled ? dataset?.cables ?? [] : [] }
    var landingPoints: [CableLandingPoint] { isEnabled ? dataset?.landingPoints ?? [] : [] }

    var selectedCable: SubmarineCable? {
        cables.first { $0.id == selectedCableID }
    }

    init(service: CableServiceProtocol, preferences: MapPreferencesStore) {
        self.service = service
        self.preferences = preferences
        activationID = preferences[.cables] ? UUID() : nil
    }

    func load(for activation: UUID?) async {
        guard let activation, activationID == activation, dataset == nil, !Task.isCancelled else { return }
        guard let loaded = try? await service.getCables(),
              activationID == activation, !Task.isCancelled else { return }
        dataset = loaded
    }

    func selectCable(_ id: String?) {
        guard id != selectedCableID, id == nil || isEnabled else { return }
        selectedCableID = id
        selectedCableDetails = nil
    }

    func loadSelectedDetails(for id: String?) async {
        guard let id, let activation = activationID, selectedCableID == id, !Task.isCancelled else { return }
        let details = try? await service.getDetails(cableID: id)
        guard activationID == activation, selectedCableID == id, !Task.isCancelled else { return }
        selectedCableDetails = details
    }
}
