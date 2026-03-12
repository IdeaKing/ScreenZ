import Foundation
import ServiceManagement

/// Manages launch-at-login registration for the main app.
enum LaunchAtLoginManager {
    static func enableIfNeeded() {
        guard SMAppService.mainApp.status != .enabled else { return }
        do {
            try SMAppService.mainApp.register()
            ScreenZLog.write("Launch at login enabled")
        } catch {
            ScreenZLog.write("❌ failed enabling launch at login: \(error.localizedDescription)")
        }
    }
}
