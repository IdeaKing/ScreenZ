import AppKit

/// Top-level coordinator that wires together the event monitor, overlay manager,
/// and window resizer. Owns all three subsystems.
///
/// Data flow:
///   `GlobalEventMonitor` → events → `AppController` → overlay + resize commands
///
/// Thread safety:
///   All closures from `GlobalEventMonitor` are delivered on the main thread.
final class AppController {

    // MARK: - Subsystems

    private let monitor        = GlobalEventMonitor()
    private let overlayManager = OverlayManager()
    private let resizer        = WindowResizer()
    private let layoutStore    = LayoutStore.shared
    private var layoutEditorOverlayController: LayoutEditorOverlayController?

    /// The window element recorded at the start of a drag gesture.
    private var trackedWindow: AXUIElement?

    private enum OperatingMode {
        case runtime
        case layoutEditor
    }
    private var mode: OperatingMode = .runtime

    var onLayoutsChanged: (() -> Void)?

    // MARK: - Init

    init() {
        wireCallbacks()
        monitor.start()
    }

    // MARK: - Layout switching (called by the status-bar menu)

    var currentLayout: ZoneLayout { overlayManager.currentLayout }
    var availableLayouts: [ZoneLayout] { layoutStore.allLayouts }
    var customLayouts: [ZoneLayout] { layoutStore.customLayouts }

    func setLayout(_ layout: ZoneLayout) {
        overlayManager.setLayout(layout)
    }

    func setLayout(_ layout: ZoneLayout, forScreenID screenID: UInt32) {
        overlayManager.setLayout(layout, forScreenID: screenID)
    }

    func clearLayoutOverride(forScreenID screenID: UInt32) {
        overlayManager.clearLayoutOverride(forScreenID: screenID)
    }

    func hasLayoutOverride(forScreenID screenID: UInt32) -> Bool {
        overlayManager.hasLayoutOverride(forScreenID: screenID)
    }

    func layout(for screen: NSScreen) -> ZoneLayout {
        overlayManager.layout(for: screen)
    }

    func layout(forScreenID screenID: UInt32) -> ZoneLayout {
        overlayManager.layout(forScreenID: screenID)
    }

    func screenID(for screen: NSScreen) -> UInt32 {
        overlayManager.screenID(for: screen)
    }

    func saveCustomLayout(_ layout: ZoneLayout, applyImmediately: Bool = true) {
        layoutStore.upsertCustomLayout(layout)
        overlayManager.refreshReferences(to: layout)
        if applyImmediately {
            setLayout(layout)
        }
        onLayoutsChanged?()
    }

    func deleteCustomLayout(id: UUID) {
        layoutStore.removeCustomLayout(id: id)
        overlayManager.removeReferences(toDeletedLayoutID: id, fallbackDefaultLayout: .sideBySide)
        onLayoutsChanged?()
    }

    func customLayout(withID id: UUID) -> ZoneLayout? {
        layoutStore.customLayouts.first { $0.id == id }
    }

    func beginLayoutEditor(
        editingCustomLayoutID layoutID: UUID? = nil,
        forceNewLayout: Bool = false,
        on screen: NSScreen? = ScreenDetector.screenAtCursor
    ) {
        guard mode == .runtime else { return }
        guard let activeScreen = screen ?? NSScreen.screens.first else { return }
        let activeScreenLayout = overlayManager.layout(for: activeScreen)

        ScreenZLog.write("[LayoutEditor] entering editor mode")
        mode = .layoutEditor
        overlayManager.hideAll()
        trackedWindow = nil
        monitor.stop()

        let initial = editorInitialLayout(
            editingCustomLayoutID: layoutID,
            forceNewLayout: forceNewLayout,
            sourceLayout: activeScreenLayout
        )
        let isEditingExistingLayout = layoutStore.customLayouts.contains { $0.id == initial.id }
        let editor = LayoutEditorOverlayController(
            screen: activeScreen,
            initialLayout: initial,
            isEditingExistingLayout: isEditingExistingLayout
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case let .saved(layout):
                ScreenZLog.write("[LayoutEditor] saved '\(layout.name)' with \(layout.zones.count) zones")
                self.saveCustomLayout(layout, applyImmediately: true)
            case .cancelled:
                ScreenZLog.write("[LayoutEditor] cancelled")
                break
            }
            self.layoutEditorOverlayController = nil
            self.mode = .runtime
            ScreenZLog.write("[LayoutEditor] returning to runtime mode")
            self.monitor.start()
        }
        layoutEditorOverlayController = editor
        editor.start()
    }

    private func editorInitialLayout(
        editingCustomLayoutID layoutID: UUID?,
        forceNewLayout: Bool,
        sourceLayout: ZoneLayout
    ) -> ZoneLayout {
        if let layoutID, let explicit = customLayout(withID: layoutID) {
            return explicit
        }
        if !forceNewLayout, let currentCustom = customLayout(withID: sourceLayout.id) {
            return currentCustom
        }
        return ZoneLayout(
            id: UUID(),
            name: nextDefaultCustomLayoutName(),
            zones: sourceLayout.zones
        )
    }

    private func nextDefaultCustomLayoutName() -> String {
        let baseName = "Custom Layout"
        let matchesName: (String) -> Bool = { candidate in
            self.layoutStore.customLayouts.contains {
                $0.name.compare(candidate, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }
        }
        if !matchesName(baseName) {
            return baseName
        }

        var suffix = 2
        while matchesName("\(baseName) \(suffix)") {
            suffix += 1
        }
        return "\(baseName) \(suffix)"
    }

    // MARK: - Callback wiring

    private func wireCallbacks() {

        // --- Drag began ---
        monitor.onDragBegan = { [weak self] cursorPoint, screen in
            guard let self else { return }
            guard self.mode == .runtime else { return }
            ScreenZLog.write("dragBegan  AX=\(PermissionManager.hasAccessibilityPermission)")
            // Capture the focused window now, before focus might shift.
            self.trackedWindow = self.resizer.frontmostWindow()
            ScreenZLog.write("trackedWindow \(self.trackedWindow == nil ? "NIL ❌" : "OK ✅")")
            self.overlayManager.show(on: screen, cursorPoint: cursorPoint)
        }

        // --- Drag moved ---
        monitor.onDragMoved = { [weak self] cursorPoint, screen in
            guard self?.mode == .runtime else { return }
            self?.overlayManager.updateCursor(at: cursorPoint, on: screen)
        }

        // --- Drag ended (mouse released) ---
        monitor.onDragEnded = { [weak self] cursorPoint, screen in
            guard let self else { return }
            guard self.mode == .runtime else { return }
            defer {
                self.overlayManager.hideAll()
                self.trackedWindow = nil
            }
            ScreenZLog.write("dragEnded at appKit=\(cursorPoint)  screen=\(screen.localizedName)")

            guard let window = self.trackedWindow else {
                ScreenZLog.write("⚠️  trackedWindow is nil — window capture failed at drag start")
                return
            }
            // Derive the zone from the mouse-up position directly for accuracy —
            // more reliable than trusting the async overlay highlight state.
            let layout = self.overlayManager.layout(for: screen)
            guard let zone = layout.zone(at: cursorPoint, on: screen) else {
                ScreenZLog.write("⚠️  no zone hit at cursor position — cursor may be outside all zones")
                return
            }
            self.resizer.snap(window: window, to: zone, on: screen)
        }

        // --- Drag cancelled (Shift released early or tap disabled) ---
        monitor.onDragCancelled = { [weak self] in
            guard self?.mode == .runtime else { return }
            ScreenZLog.write("dragCancelled (Shift released before mouse-up, or tap disabled)")
            self?.overlayManager.hideAll()
            self?.trackedWindow = nil
        }
    }
}
