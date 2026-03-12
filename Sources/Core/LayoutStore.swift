import Foundation

/// Persists user-defined custom layouts to UserDefaults.
final class LayoutStore {
    static let shared = LayoutStore()

    private enum Keys {
        static let customLayouts = "screenz.customLayouts.v1"
    }

    private let defaults: UserDefaults
    private(set) var customLayouts: [ZoneLayout]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.customLayouts = Self.loadCustomLayouts(from: defaults)
    }

    var allLayouts: [ZoneLayout] {
        ZoneLayout.builtIn + customLayouts
    }

    func upsertCustomLayout(_ layout: ZoneLayout) {
        if let index = customLayouts.firstIndex(where: { $0.id == layout.id }) {
            customLayouts[index] = layout
        } else {
            customLayouts.append(layout)
        }
        persist()
    }

    func removeCustomLayout(id: UUID) {
        customLayouts.removeAll { $0.id == id }
        persist()
    }

    // MARK: - Private

    private func persist() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(customLayouts) {
            defaults.set(data, forKey: Keys.customLayouts)
        }
    }

    private static func loadCustomLayouts(from defaults: UserDefaults) -> [ZoneLayout] {
        guard let data = defaults.data(forKey: Keys.customLayouts) else { return [] }
        let decoder = JSONDecoder()
        return (try? decoder.decode([ZoneLayout].self, from: data)) ?? []
    }
}
