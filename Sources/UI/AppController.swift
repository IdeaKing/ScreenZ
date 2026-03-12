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

    /// The window element recorded at the start of a drag gesture.
    private var trackedWindow: AXUIElement?

    // MARK: - Init

    init() {
        wireCallbacks()
        monitor.start()
    }

    // MARK: - Layout switching (called by the status-bar menu)

    func setLayout(_ layout: ZoneLayout) {
        overlayManager.setLayout(layout)
    }

    var currentLayout: ZoneLayout { overlayManager.currentLayout }
    var availableLayouts: [ZoneLayout] { layoutStore.allLayouts }

    func saveCustomLayout(_ layout: ZoneLayout, applyImmediately: Bool = true) {
        layoutStore.upsertCustomLayout(layout)
        if applyImmediately {
            setLayout(layout)
        }
    }

    func deleteCustomLayout(id: UUID) {
        layoutStore.removeCustomLayout(id: id)
        if currentLayout.id == id {
            setLayout(.halves)
        }
    }

    // MARK: - Callback wiring

    private func wireCallbacks() {

        // --- Drag began ---
        monitor.onDragBegan = { [weak self] cursorPoint, screen in
            guard let self else { return }
            ScreenZLog.write("dragBegan  AX=\(PermissionManager.hasAccessibilityPermission)")
            // Capture the focused window now, before focus might shift.
            self.trackedWindow = self.resizer.frontmostWindow()
            ScreenZLog.write("trackedWindow \(self.trackedWindow == nil ? "NIL ❌" : "OK ✅")")
            self.overlayManager.show(on: screen, cursorPoint: cursorPoint)
        }

        // --- Drag moved ---
        monitor.onDragMoved = { [weak self] cursorPoint, screen in
            self?.overlayManager.updateCursor(at: cursorPoint, on: screen)
        }

        // --- Drag ended (mouse released) ---
        monitor.onDragEnded = { [weak self] cursorPoint, screen in
            guard let self else { return }
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
            guard let zone = self.overlayManager.currentLayout.zone(at: cursorPoint, on: screen) else {
                ScreenZLog.write("⚠️  no zone hit at cursor position — cursor may be outside all zones")
                return
            }
            self.resizer.snap(window: window, to: zone, on: screen)
        }

        // --- Drag cancelled (Shift released early or tap disabled) ---
        monitor.onDragCancelled = { [weak self] in
            ScreenZLog.write("dragCancelled (Shift released before mouse-up, or tap disabled)")
            self?.overlayManager.hideAll()
            self?.trackedWindow = nil
        }
    }
}
