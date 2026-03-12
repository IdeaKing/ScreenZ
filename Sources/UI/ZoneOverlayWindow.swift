import AppKit

/// A borderless, fully transparent, non-interactive window that covers exactly
/// one NSScreen and renders the drop-zone overlay via a `ZoneOverlayView`.
///
/// One `ZoneOverlayWindow` is created per physical display and kept alive for the
/// duration of the app session. Visibility is controlled by the `OverlayManager`.
final class ZoneOverlayWindow: NSWindow {

    // MARK: - Subviews

    /// Implicitly unwrapped optional: must be nil-able during the NSWindow two-phase
    /// init, which on macOS 26 routes through the ObjC 4-param thunk before returning
    /// to our designated init. The view is always set before the window is used.
    private(set) var overlayView: ZoneOverlayView!

    // MARK: - Init

    init(screen: NSScreen, layout: ZoneLayout) {
        // Phase 1 — call the 4-param NSWindow designated initialiser.
        // Do NOT use the 5-param screen: variant; on macOS 26 it re-enters this
        // subclass's ObjC thunk before phase 2 runs, crashing on the unset overlayView.
        super.init(
            contentRect: screen.frame,   // Temporary rect; setFrame below overrides it.
            styleMask:   [.borderless],
            backing:     .buffered,
            defer:       false
        )

        // Phase 2 — configure inherited NSWindow properties.

        // Place the overlay above all normal windows but below screensavers/notifications.
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)

        backgroundColor = .clear
        isOpaque        = false

        // Never steal focus or intercept mouse events — raw CGEvents are read directly
        // by GlobalEventMonitor, so the overlay window needs zero interactivity.
        ignoresMouseEvents      = true
        acceptsMouseMovedEvents = false

        // Appear on every Space and in Exposé without stealing focus.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        // Start invisible; OverlayManager calls show()/hide() with animation.
        alphaValue           = 0
        isReleasedWhenClosed = false

        // Create and assign the content view after super.init is complete.
        let view = ZoneOverlayView(screen: screen, layout: layout)
        overlayView  = view
        contentView  = view

        // Position precisely on the target screen (the initial contentRect is just a hint).
        setFrame(screen.frame, display: false)

        // Insert into the window server without activating the app.
        orderFrontRegardless()
    }

    // MARK: - Overlay state helpers

    /// Shows the overlay by fading in.
    func show(animationDuration: TimeInterval = 0.15) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = animationDuration
            animator().alphaValue = 1
        }
    }

    /// Hides the overlay by fading out.
    func hide(animationDuration: TimeInterval = 0.20) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = animationDuration
            animator().alphaValue = 0
        }
    }

    /// Updates which zone appears highlighted and redraws immediately.
    func highlight(zoneID: UUID?) {
        overlayView.highlightedZoneID = zoneID
    }

    /// Swaps in a new layout and triggers a redraw.
    func apply(layout: ZoneLayout) {
        overlayView.layout = layout
    }

    /// Rebinds this overlay window to a changed screen geometry.
    func update(screen: NSScreen) {
        overlayView.screen = screen
        overlayView.frame = CGRect(origin: .zero, size: screen.frame.size)
        setFrame(screen.frame, display: false)
        overlayView.needsDisplay = true
    }

    // MARK: - NSWindow overrides

    override var canBecomeKey:  Bool { false }
    override var canBecomeMain: Bool { false }
}
