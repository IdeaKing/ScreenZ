import AppKit

// Entry point is in main.swift; @NSApplicationMain is not used with SPM.
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    private var controller: AppController?
    private var statusItem: NSStatusItem?

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as a menu-bar-only app — no Dock icon, no activation on launch.
        NSApp.setActivationPolicy(.accessory)

        let hasPerm = PermissionManager.hasAccessibilityPermission
        ScreenZLog.write("=== ScreenZ launched ===")
        ScreenZLog.write("log path: \(ScreenZLog.path)")
        ScreenZLog.write("bundle path: \(Bundle.main.bundlePath)")
        ScreenZLog.write("exec path: \(Bundle.main.executablePath ?? CommandLine.arguments[0])")
        ScreenZLog.write("bundle id: \(Bundle.main.bundleIdentifier ?? "nil")")
        ScreenZLog.write("Accessibility: \(hasPerm)")
        ScreenZLog.write("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")

        // Request Accessibility permission. If not yet granted, macOS shows a system
        // dialog directing the user to System Settings → Privacy & Security → Accessibility.
        if !PermissionManager.requestIfNeeded() {
            // Permission denied or not yet decided — show our own explanatory alert.
            PermissionManager.showPermissionAlert()
        }

        // Start the event monitor and wiring only after permission handling.
        // If the user grants permission during this session, they need to relaunch.
        controller = AppController()
        controller?.onLayoutsChanged = { [weak self] in
            self?.reloadMenu()
        }
        setupStatusBar()
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusItem = nil
    }

    // MARK: - Status-bar menu

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            // SF Symbol available on macOS 11+; falls back gracefully on older versions.
            if let icon = NSImage(systemSymbolName: "rectangle.3.group.fill",
                                  accessibilityDescription: "ScreenZ") {
                icon.isTemplate = true   // Adapts to light/dark menu bar automatically.
                button.image = icon
            }
            button.toolTip = "ScreenZ — Window Zones (Hold ⇧ while dragging a window)"
        }

        statusItem?.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // --- App header ---
        let header = NSMenuItem(title: "ScreenZ", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        // --- Layout submenu ---
        let layoutItem = NSMenuItem(title: "Layout", action: nil, keyEquivalent: "")
        layoutItem.submenu = buildLayoutSubmenu()
        menu.addItem(layoutItem)
        let customLayoutsItem = NSMenuItem(
            title: "Layout Editor…",
            action: #selector(openLayoutEditor),
            keyEquivalent: "")
        customLayoutsItem.target = self
        menu.addItem(customLayoutsItem)

        let deleteCustomLayoutItem = NSMenuItem(title: "Delete Custom Layout", action: nil, keyEquivalent: "")
        deleteCustomLayoutItem.submenu = buildDeleteCustomLayoutSubmenu()
        menu.addItem(deleteCustomLayoutItem)
        menu.addItem(.separator())

        // --- Usage hint ---
        let hint = NSMenuItem(
            title: "Hold ⇧ while dragging to snap",
            action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())

        // --- Accessibility ---
        let accessibilityItem = NSMenuItem(
            title: "Open Accessibility Settings…",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: "")
        accessibilityItem.target = self
        menu.addItem(accessibilityItem)

        menu.addItem(.separator())

        // --- Quit ---
        menu.addItem(NSMenuItem(
            title: "Quit ScreenZ",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"))

        return menu
    }

    private func buildLayoutSubmenu() -> NSMenu {
        let sub = NSMenu()
        let layouts = controller?.availableLayouts ?? ZoneLayout.all
        for layout in layouts {
            let item = NSMenuItem(
                title: layout.name,
                action: #selector(selectLayout(_:)),
                keyEquivalent: "")
            item.representedObject = layout
            item.target = self
            item.state = (layout.id == controller?.currentLayout.id) ? .on : .off
            sub.addItem(item)
        }
        return sub
    }

    private func buildDeleteCustomLayoutSubmenu() -> NSMenu {
        let sub = NSMenu()
        let customLayouts = (controller?.customLayouts ?? []).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        if customLayouts.isEmpty {
            let noneItem = NSMenuItem(title: "No custom layouts", action: nil, keyEquivalent: "")
            noneItem.isEnabled = false
            sub.addItem(noneItem)
            return sub
        }

        for layout in customLayouts {
            let isCurrent = layout.id == controller?.currentLayout.id
            let title = isCurrent ? "\(layout.name) (Active)" : layout.name
            let item = NSMenuItem(
                title: title,
                action: #selector(deleteCustomLayout(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = layout.id
            sub.addItem(item)
        }
        return sub
    }

    // MARK: - Actions

    @objc private func selectLayout(_ sender: NSMenuItem) {
        guard let layout = sender.representedObject as? ZoneLayout else { return }
        controller?.setLayout(layout)

        // Update the checkmark in the submenu.
        if let submenu = sender.menu {
            submenu.items.forEach { $0.state = .off }
            sender.state = .on
        }
    }

    @objc private func openAccessibilitySettings() {
        PermissionManager.openSystemSettings()
    }

    @objc private func openLayoutEditor() {
        controller?.beginLayoutEditor()
    }

    @objc private func deleteCustomLayout(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        guard let layout = controller?.customLayouts.first(where: { $0.id == id }) else { return }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Delete '\(layout.name)'?"
        alert.informativeText = "This removes the custom layout from ScreenZ."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            controller?.deleteCustomLayout(id: id)
        }
    }

    private func reloadMenu() {
        statusItem?.menu = buildMenu()
    }
}
