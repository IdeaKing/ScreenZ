import AppKit

/// Manages Accessibility permission requests and status checks.
enum PermissionManager {

    // MARK: - Status

    /// `true` when the app has been granted Accessibility access.
    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    // MARK: - Requesting permission

    /// Triggers the system permission prompt (if not already granted) and returns
    /// whether the permission is currently active.
    ///
    /// Call once at launch. macOS will show a dialog the first time; subsequent calls
    /// are silent if the user has already granted or denied.
    @discardableResult
    static func requestIfNeeded() -> Bool {
        guard !hasAccessibilityPermission else { return true }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Opens System Settings → Privacy & Security → Accessibility so the user can
    /// toggle the switch for this app manually.
    static func openSystemSettings() {
        let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Alert helper

    /// Shows a modal alert explaining that Accessibility is required, with a button
    /// that opens System Settings.
    static func showPermissionAlert() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText =
            "ScreenZ needs Accessibility access to detect window drags and move windows.\n\n" +
            "If you launch using swift run, enable Terminal too.\n\n" +
            "Open System Settings → Privacy & Security → Accessibility and enable the exact running app."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            openSystemSettings()
        }
    }
}
