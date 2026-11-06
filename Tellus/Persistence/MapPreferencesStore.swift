import Foundation

enum MapLayer: String {
    case flights = "showsFlights"
    case hazards = "showsHazards"
    case cables = "showsCables"
    case powerGrid = "showsPowerGrid"
    case earthAtNight = "showsEarthAtNight"
    case viirsImagery = "showsVIIRSImagery"
}

protocol MapPreferencesStore: AnyObject {
    var nationality: Country? { get set }
    subscript(layer: MapLayer) -> Bool { get set }
}

final class UserDefaultsMapPreferencesStore: MapPreferencesStore {
    private let defaults: UserDefaults
    private let nationalityKey = "nationality"

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    var nationality: Country? {
        get {
            guard let data = defaults.data(forKey: nationalityKey) else { return nil }
            return try? JSONDecoder().decode(Country.self, from: data)
        }
        set {
            guard let newValue else {
                defaults.removeObject(forKey: nationalityKey)
                return
            }
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: nationalityKey)
            }
        }
    }

    subscript(layer: MapLayer) -> Bool {
        get {
            if let stored = defaults.object(forKey: layer.rawValue) as? Bool {
                return stored
            }
            switch layer {
            case .flights, .hazards:
                return true
            case .earthAtNight:
                return defaults.bool(forKey: "showsDayNight") || defaults.bool(forKey: "showsNightLights")
            case .cables, .powerGrid, .viirsImagery:
                return false
            }
        }
        set {
            defaults.set(newValue, forKey: layer.rawValue)
        }
    }
}
