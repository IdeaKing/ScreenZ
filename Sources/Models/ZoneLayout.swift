import AppKit

/// A named, ordered collection of drop zones representing one complete layout.
struct ZoneLayout: Identifiable, Equatable, Codable {
    let id: UUID
    let name: String
    let zones: [Zone]

    init(id: UUID = UUID(), name: String, zones: [Zone]) {
        self.id = id
        self.name = name
        self.zones = zones
    }

    // MARK: - Hit testing

    /// Returns the first zone whose screen rect contains `point` (AppKit coordinates).
    func zone(at point: CGPoint, on screen: NSScreen) -> Zone? {
        zones.first { $0.screenRect(in: screen.visibleFrame).contains(point) }
    }

    // MARK: - Built-in layouts

    /// Two vertical halves + two horizontal halves (4 zones, some overlap by design).
    static let halves = ZoneLayout(name: "Halves", zones: [
        Zone(name: "Left Half",   x: 0.0, y: 0.0, width: 0.5, height: 1.0),
        Zone(name: "Right Half",  x: 0.5, y: 0.0, width: 0.5, height: 1.0),
        Zone(name: "Top Half",    x: 0.0, y: 0.5, width: 1.0, height: 0.5),
        Zone(name: "Bottom Half", x: 0.0, y: 0.0, width: 1.0, height: 0.5),
    ])

    /// Four non-overlapping corner quarters.
    static let quarters = ZoneLayout(name: "Quarters", zones: [
        Zone(name: "Top-Left",     x: 0.0, y: 0.5, width: 0.5, height: 0.5),
        Zone(name: "Top-Right",    x: 0.5, y: 0.5, width: 0.5, height: 0.5),
        Zone(name: "Bottom-Left",  x: 0.0, y: 0.0, width: 0.5, height: 0.5),
        Zone(name: "Bottom-Right", x: 0.5, y: 0.0, width: 0.5, height: 0.5),
    ])

    /// Three equal vertical columns.
    static let thirds = ZoneLayout(name: "Thirds", zones: [
        Zone(name: "Left Third",   x: 0.0 / 3.0, y: 0.0, width: 1.0 / 3.0, height: 1.0),
        Zone(name: "Center Third", x: 1.0 / 3.0, y: 0.0, width: 1.0 / 3.0, height: 1.0),
        Zone(name: "Right Third",  x: 2.0 / 3.0, y: 0.0, width: 1.0 / 3.0, height: 1.0),
    ])

    /// 3×2 grid (three columns, two rows = six zones).
    static let sixths = ZoneLayout(name: "3×2 Grid", zones: [
        Zone(name: "Top-Left",      x: 0.0 / 3.0, y: 0.5, width: 1.0 / 3.0, height: 0.5),
        Zone(name: "Top-Center",    x: 1.0 / 3.0, y: 0.5, width: 1.0 / 3.0, height: 0.5),
        Zone(name: "Top-Right",     x: 2.0 / 3.0, y: 0.5, width: 1.0 / 3.0, height: 0.5),
        Zone(name: "Bottom-Left",   x: 0.0 / 3.0, y: 0.0, width: 1.0 / 3.0, height: 0.5),
        Zone(name: "Bottom-Center", x: 1.0 / 3.0, y: 0.0, width: 1.0 / 3.0, height: 0.5),
        Zone(name: "Bottom-Right",  x: 2.0 / 3.0, y: 0.0, width: 1.0 / 3.0, height: 0.5),
    ])

    /// Wide center + narrow sides (Priority layout).
    static let priority = ZoneLayout(name: "Priority", zones: [
        Zone(name: "Left Sidebar",  x: 0.0,       y: 0.0, width: 0.25,      height: 1.0),
        Zone(name: "Main",          x: 0.25,      y: 0.0, width: 0.5,       height: 1.0),
        Zone(name: "Right Sidebar", x: 0.75,      y: 0.0, width: 0.25,      height: 1.0),
    ])

    static let builtIn: [ZoneLayout] = [.halves, .quarters, .thirds, .sixths, .priority]
    static let all: [ZoneLayout] = builtIn
}
