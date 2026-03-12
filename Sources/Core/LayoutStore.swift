import Foundation

/// Persists user-defined custom layouts as JSON in Application Support.
final class LayoutStore {
    static let shared = LayoutStore()

    private let fileURL: URL
    private(set) var customLayouts: [ZoneLayout]

    init(fileURL: URL = LayoutStore.defaultFileURL()) {
        self.fileURL = fileURL
        self.customLayouts = Self.loadCustomLayouts(from: fileURL)
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
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(customLayouts) else { return }
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            ScreenZLog.write("❌ failed writing layout config JSON: \(error.localizedDescription)")
        }
    }

    private static func loadCustomLayouts(from fileURL: URL) -> [ZoneLayout] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        return (try? decoder.decode([ZoneLayout].self, from: data)) ?? []
    }

    private static func defaultFileURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport
            .appendingPathComponent("ScreenZ", isDirectory: true)
            .appendingPathComponent("layouts.json", isDirectory: false)
    }
}
