import AppKit

/// Creates, caches, and coordinates all `ZoneOverlayWindow` instances — one per screen.
///
/// Responsibilities:
/// - Allocating overlay windows on first use and recycling them across drags.
/// - Showing / hiding the overlay on the correct screen.
/// - Forwarding cursor-position updates to highlight the correct zone.
/// - Rebuilding overlays when the screen configuration changes.
final class OverlayManager {

    // MARK: - State

    /// Keyed by the screen's unique `deviceDescription["NSScreenNumber"]` UInt32.
    private var overlaysByScreenID: [UInt32: ZoneOverlayWindow] = [:]

    /// The screen that currently has an active (visible) overlay, if any.
    private var activeScreen: NSScreen?

    /// Default layout used by screens that do not have an explicit override.
    private(set) var currentLayout: ZoneLayout = .sideBySide
    /// Per-screen layout overrides keyed by screen device ID.
    private var layoutOverridesByScreenID: [UInt32: ZoneLayout] = [:]

    // MARK: - Init

    init() {
        // Rebuild cached overlay windows whenever displays are added, removed, or
        // reconfigured (resolution change, mirror changes, etc.).
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public API

    /// Selects the layout used for all subsequent drags.
    func setLayout(_ layout: ZoneLayout) {
        currentLayout = layout
        for (id, window) in overlaysByScreenID {
            window.apply(layout: resolvedLayout(forScreenID: id))
        }
    }

    /// Sets an explicit layout for one screen.
    func setLayout(_ layout: ZoneLayout, forScreenID screenID: UInt32) {
        layoutOverridesByScreenID[screenID] = layout
        overlaysByScreenID[screenID]?.apply(layout: layout)
    }

    /// Clears the explicit layout for one screen, returning it to the default layout.
    func clearLayoutOverride(forScreenID screenID: UInt32) {
        layoutOverridesByScreenID.removeValue(forKey: screenID)
        overlaysByScreenID[screenID]?.apply(layout: currentLayout)
    }

    func hasLayoutOverride(forScreenID screenID: UInt32) -> Bool {
        layoutOverridesByScreenID[screenID] != nil
    }

    func layout(for screen: NSScreen) -> ZoneLayout {
        resolvedLayout(forScreenID: screenID(for: screen))
    }

    func layout(forScreenID screenID: UInt32) -> ZoneLayout {
        resolvedLayout(forScreenID: screenID)
    }

    /// Updates default/override references when a layout with the same ID is saved.
    func refreshReferences(to layout: ZoneLayout) {
        if currentLayout.id == layout.id {
            currentLayout = layout
        }
        for (screenID, assigned) in layoutOverridesByScreenID where assigned.id == layout.id {
            layoutOverridesByScreenID[screenID] = layout
        }
        for (screenID, window) in overlaysByScreenID {
            window.apply(layout: resolvedLayout(forScreenID: screenID))
        }
    }

    /// Removes references to a deleted layout.
    /// If the deleted layout was the default, `fallbackDefaultLayout` is used.
    func removeReferences(
        toDeletedLayoutID layoutID: UUID,
        fallbackDefaultLayout: ZoneLayout
    ) {
        if currentLayout.id == layoutID {
            currentLayout = fallbackDefaultLayout
        }
        layoutOverridesByScreenID = layoutOverridesByScreenID.filter { $0.value.id != layoutID }
        for (screenID, window) in overlaysByScreenID {
            window.apply(layout: resolvedLayout(forScreenID: screenID))
        }
    }

    /// Shows the overlay on `screen` and hides any overlay on other screens.
    /// - Parameter cursorPoint: Optional initial cursor position (AppKit coords) used to
    ///   pre-highlight a zone before the first `updateCursor` call.
    func show(on screen: NSScreen, cursorPoint: CGPoint? = nil) {
        hideAll(animated: false)
        activeScreen = screen

        let overlay = overlayWindow(for: screen)
        let layout = resolvedLayout(forScreenID: screenID(for: screen))
        overlay.apply(layout: layout)
        if let point = cursorPoint {
            let zone = layout.zone(at: point, on: screen)
            overlay.highlight(zoneID: zone?.id)
        }
        overlay.show()
    }

    /// Updates the highlighted zone based on the current cursor position.
    /// Must be called on the main thread.
    func updateCursor(at appKitPoint: CGPoint, on screen: NSScreen) {
        // If the cursor moved to a different screen, swap the active overlay.
        if let active = activeScreen, active != screen {
            overlayWindow(for: active).hide()
            activeScreen = screen
            overlayWindow(for: screen).show(animationDuration: 0.08)
        }

        let screenID = screenID(for: screen)
        let layout = resolvedLayout(forScreenID: screenID)
        let overlay = overlayWindow(for: screen)
        overlay.apply(layout: layout)
        let zone = layout.zone(at: appKitPoint, on: screen)
        overlay.highlight(zoneID: zone?.id)
    }

    /// Returns the zone currently highlighted on `screen`, or `nil`.
    func highlightedZone(on screen: NSScreen) -> Zone? {
        guard let id = overlayWindow(for: screen).overlayView.highlightedZoneID else { return nil }
        return resolvedLayout(forScreenID: screenID(for: screen)).zones.first { $0.id == id }
    }

    /// Hides all overlay windows.
    func hideAll(animated: Bool = true) {
        overlaysByScreenID.values.forEach { animated ? $0.hide() : ($0.alphaValue = 0) }
        activeScreen = nil
    }

    // MARK: - Private helpers

    /// Returns (and lazily creates) the overlay window for `screen`.
    private func overlayWindow(for screen: NSScreen) -> ZoneOverlayWindow {
        let screenID = self.screenID(for: screen)
        if let existing = overlaysByScreenID[screenID] { return existing }

        let window = ZoneOverlayWindow(screen: screen, layout: resolvedLayout(forScreenID: screenID))
        overlaysByScreenID[screenID] = window
        return window
    }

    func screenID(for screen: NSScreen) -> UInt32 {
        if let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return n.uint32Value
        }
        return (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) ?? 0
    }

    private func resolvedLayout(forScreenID screenID: UInt32) -> ZoneLayout {
        layoutOverridesByScreenID[screenID] ?? currentLayout
    }

    // MARK: - Screen change handling

    @objc private func screensChanged() {
        let screensByID = Dictionary(uniqueKeysWithValues: NSScreen.screens.map { (screenID(for: $0), $0) })

        // Tear down overlays for disconnected screens; update geometry for survivors.
        for id in Array(overlaysByScreenID.keys) {
            guard let screen = screensByID[id] else {
                overlaysByScreenID[id]?.close()
                overlaysByScreenID.removeValue(forKey: id)
                continue
            }
            overlaysByScreenID[id]?.update(screen: screen)
            overlaysByScreenID[id]?.apply(layout: resolvedLayout(forScreenID: id))
        }
        layoutOverridesByScreenID = layoutOverridesByScreenID.filter { screensByID[$0.key] != nil }

        if let activeScreen {
            self.activeScreen = screensByID[screenID(for: activeScreen)]
        }
    }
}
