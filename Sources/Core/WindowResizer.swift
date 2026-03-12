import AppKit

/// Moves and resizes windows using the macOS Accessibility API (AXUIElement).
///
/// All public methods must be called on the **main thread**.
/// The app must have Accessibility permission (checked via `PermissionManager`).
final class WindowResizer {

    // MARK: - Frontmost window

    /// Returns an AXUIElement for the focused window of the frontmost application.
    ///
    /// This is the window the user is most likely dragging. Call this as soon as a
    /// drag gesture begins, before the focus may change.
    func frontmostWindow() -> AXUIElement? {
        guard PermissionManager.hasAccessibilityPermission else {
            log("⚠️  Accessibility permission is not granted; cannot access focused window")
            return nil
        }

        if let app = NSWorkspace.shared.frontmostApplication {
            log("🔍 frontmost app: \(app.localizedName ?? "?") pid=\(app.processIdentifier)")
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            if let window = focusedWindow(from: axApp) {
                log("✅ got focused window element from frontmost app")
                return window
            }
            log("⚠️  frontmost app has no readable focused window; trying system-wide fallback")
        }

        if let fallback = systemWideFocusedWindow() {
            log("✅ got focused window element from system-wide fallback")
            return fallback
        }

        log("⚠️  unable to resolve a focused window element")
        return nil
    }

    // MARK: - Snapping

    /// Moves and resizes `window` so it fills the given `zone` on `screen`.
    ///
    /// - Parameters:
    ///   - window: An AXUIElement obtained from `frontmostWindow()`.
    ///   - zone:   The target drop zone.
    ///   - screen: The screen that contains the zone.
    func snap(window: AXUIElement, to zone: Zone, on screen: NSScreen) {
        let targetRect = zone.screenRect(in: screen.visibleFrame)
        log("🎯 snap → zone '\(zone.name)'  appKitRect=\(targetRect)")
        let cgPos = ScreenDetector.cgPosition(fromAppKitRect: targetRect)
        log("   CG position=\(cgPos)  size=\(targetRect.size)")
        setFrame(targetRect, for: window)
    }

    // MARK: - Private helpers

    /// Sets the position and size of `window` using the AX API.
    ///
    /// AXUIElement positions use **CoreGraphics coordinates** (top-left origin, y downward),
    /// so we convert from the AppKit rect using `ScreenDetector.cgPosition(fromAppKitRect:)`.
    private func setFrame(_ appKitRect: CGRect, for window: AXUIElement) {
        // -- Position (top-left corner in CG coords) --
        var cgOrigin = ScreenDetector.cgPosition(fromAppKitRect: appKitRect)
        guard let posValue = AXValueCreate(.cgPoint, &cgOrigin) else {
            logAXError("AXValueCreate(.cgPoint) returned nil"); return
        }
        let posResult = AXUIElementSetAttributeValue(
            window, kAXPositionAttribute as CFString, posValue)
        if posResult != .success { logAXError("kAXPosition set failed: \(posResult.rawValue)") }

        // -- Size --
        var size = appKitRect.size
        guard let sizeValue = AXValueCreate(.cgSize, &size) else {
            logAXError("AXValueCreate(.cgSize) returned nil"); return
        }
        let sizeResult = AXUIElementSetAttributeValue(
            window, kAXSizeAttribute as CFString, sizeValue)
        if sizeResult != .success { logAXError("kAXSize set failed: \(sizeResult.rawValue)") }
    }

    private func focusedWindow(from appElement: AXUIElement) -> AXUIElement? {
        var windowRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement, kAXFocusedWindowAttribute as CFString, &windowRef)
        guard result == .success, let windowRef else {
            log("⚠️  kAXFocusedWindow failed: AXError \(result.rawValue)")
            return nil
        }
        return axElement(from: windowRef)
    }

    private func systemWideFocusedWindow() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()

        var windowRef: CFTypeRef?
        let focusedWindowResult = AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedWindowAttribute as CFString, &windowRef)
        if focusedWindowResult == .success, let windowRef, let window = axElement(from: windowRef) {
            return window
        }

        var focusedUIRef: CFTypeRef?
        let focusedUIResult = AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focusedUIRef)
        guard focusedUIResult == .success,
              let focusedUIRef,
              let focusedElement = axElement(from: focusedUIRef)
        else {
            return nil
        }

        var parentWindowRef: CFTypeRef?
        let parentWindowResult = AXUIElementCopyAttributeValue(
            focusedElement, kAXWindowAttribute as CFString, &parentWindowRef)
        guard parentWindowResult == .success, let parentWindowRef else { return nil }
        return axElement(from: parentWindowRef)
    }

    private func axElement(from ref: CFTypeRef) -> AXUIElement? {
        guard CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        // swiftlint:disable:next force_cast
        return (ref as! AXUIElement)
    }

    // MARK: - Diagnostics

    /// Returns the current frame of `window` in AppKit screen coordinates, if readable.
    func currentFrame(of window: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?

        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posVal = posRef, let sizeVal = sizeRef
        else { return nil }

        var cgPoint = CGPoint.zero
        var cgSize = CGSize.zero
        // swiftlint:disable force_cast
        AXValueGetValue(posVal as! AXValue, .cgPoint, &cgPoint)
        AXValueGetValue(sizeVal as! AXValue, .cgSize, &cgSize)
        // swiftlint:enable force_cast

        // Convert CG top-left position back to AppKit.
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        let appKitOrigin = CGPoint(x: cgPoint.x, y: primaryH - cgPoint.y - cgSize.height)
        return CGRect(origin: appKitOrigin, size: cgSize)
    }

    private func log(_ message: String) {
        ScreenZLog.write(message)
    }

    private func logAXError(_ message: String) {
        ScreenZLog.write("[AXError] \(message)")
    }
}
