import AppKit

// Suppress the Dock icon before NSApplication finishes launching.
// (AppDelegate also calls this, but setting it here avoids a brief flash.)
NSApplication.shared.setActivationPolicy(.accessory)

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
