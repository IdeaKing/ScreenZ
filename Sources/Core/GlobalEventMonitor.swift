import AppKit
import CoreGraphics

/// Monitors global mouse-drag gestures and emits Shift+drag lifecycle callbacks.
///
/// Implementation notes:
/// - Uses AppKit global event monitors for mouse drag/up (reliable in background apps).
/// - Uses `CGEventSource.keyState` to read Shift state directly, avoiding fragile
///   dependency on keyboard-event delivery.
final class GlobalEventMonitor {

    // MARK: - Callbacks (set by AppController)

    /// Called once when a Shift+drag begins. Provides the AppKit cursor position and screen.
    var onDragBegan: ((_ cursorPoint: CGPoint, _ screen: NSScreen) -> Void)?

    /// Called repeatedly while the drag continues. Provides updated cursor position and screen.
    var onDragMoved: ((_ cursorPoint: CGPoint, _ screen: NSScreen) -> Void)?

    /// Called when the mouse button is released while the overlay is active.
    var onDragEnded: ((_ cursorPoint: CGPoint, _ screen: NSScreen) -> Void)?

    /// Called when the drag is cancelled (Shift released before mouse up).
    var onDragCancelled: (() -> Void)?

    // MARK: - Private state

    private var mouseDraggedMonitor: Any?
    private var mouseUpMonitor: Any?
    private var isOverlayActive = false
    private var shiftPollTimer: Timer?

    // MARK: - Lifecycle

    /// Installs global mouse monitors.
    func start() {
        guard mouseDraggedMonitor == nil, mouseUpMonitor == nil else { return }

        mouseDraggedMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] event in
            self?.handleMouseDragged(event)
        }
        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            self?.handleMouseUp(event)
        }

        if mouseDraggedMonitor == nil || mouseUpMonitor == nil {
            ScreenZLog.write("global event monitors failed to install ❌")
        } else {
            ScreenZLog.write("global event monitors installed ✅")
        }
    }

    /// Removes all installed monitors and timers.
    func stop() {
        if let monitor = mouseDraggedMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = mouseUpMonitor {
            NSEvent.removeMonitor(monitor)
        }
        mouseDraggedMonitor = nil
        mouseUpMonitor = nil
        stopShiftPolling()
        isOverlayActive = false
    }

    deinit {
        stop()
    }

    // MARK: - Per-event handlers

    private func handleMouseDragged(_ event: NSEvent) {
        let _ = event

        guard Self.isShiftDown else {
            if isOverlayActive {
                cancelActiveDrag()
            }
            return
        }

        let appKitPoint = NSEvent.mouseLocation
        guard let screen = ScreenDetector.screen(at: appKitPoint) else { return }

        if !isOverlayActive {
            isOverlayActive = true
            startShiftPolling()
            onDragBegan?(appKitPoint, screen)
        } else {
            onDragMoved?(appKitPoint, screen)
        }
    }

    private func handleMouseUp(_ event: NSEvent) {
        let _ = event
        guard isOverlayActive else { return }

        isOverlayActive = false
        stopShiftPolling()

        let appKitPoint = NSEvent.mouseLocation
        let screen = ScreenDetector.screen(at: appKitPoint) ?? NSScreen.screens.first

        if let screen {
            onDragEnded?(appKitPoint, screen)
        } else {
            onDragCancelled?()
        }
    }

    // MARK: - Shift state

    private func startShiftPolling() {
        guard shiftPollTimer == nil else { return }

        // Cancel promptly if Shift is released while the mouse is stationary.
        shiftPollTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard self.isOverlayActive else { return }
            if !Self.isShiftDown {
                self.cancelActiveDrag()
            }
        }
        if let shiftPollTimer {
            RunLoop.main.add(shiftPollTimer, forMode: .common)
        }
    }

    private func stopShiftPolling() {
        shiftPollTimer?.invalidate()
        shiftPollTimer = nil
    }

    private func cancelActiveDrag() {
        guard isOverlayActive else { return }
        isOverlayActive = false
        stopShiftPolling()
        onDragCancelled?()
    }

    private static var isShiftDown: Bool {
        let sourceState = CGEventSourceStateID.combinedSessionState
        return CGEventSource.keyState(sourceState, key: 56) || CGEventSource.keyState(sourceState, key: 60)
    }
}
