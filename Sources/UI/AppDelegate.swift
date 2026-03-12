import AppKit

// Entry point is in main.swift; @NSApplicationMain is not used with SPM.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private struct ScreenLayoutSelection {
        let screenID: UInt32
        let layoutID: UUID?
    }

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

        // Request Accessibility permission only when not already granted.
        if !hasPerm {
            // If still unavailable after requesting, show guidance.
            if !PermissionManager.requestIfNeeded() {
                PermissionManager.showPermissionAlert()
            }
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

        // --- Layout selector ---
        let layoutItem = NSMenuItem(title: "Default Layout", action: nil, keyEquivalent: "")
        layoutItem.submenu = buildLayoutSubmenu()
        menu.addItem(layoutItem)

        let screenLayoutsItem = NSMenuItem(title: "Screen Layouts", action: nil, keyEquivalent: "")
        screenLayoutsItem.submenu = buildScreenLayoutsSubmenu()
        menu.addItem(screenLayoutsItem)

        // --- Custom layout management ---
        let customLayoutsItem = NSMenuItem(title: "Custom Layouts", action: nil, keyEquivalent: "")
        customLayoutsItem.submenu = buildCustomLayoutsSubmenu()
        menu.addItem(customLayoutsItem)
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
        let currentID = controller?.currentLayout.id

        let builtInHeader = NSMenuItem(title: "Built-in", action: nil, keyEquivalent: "")
        builtInHeader.isEnabled = false
        sub.addItem(builtInHeader)

        for layout in ZoneLayout.builtIn {
            let item = NSMenuItem(
                title: layout.name,
                action: #selector(selectLayout(_:)),
                keyEquivalent: "")
            item.representedObject = layout
            item.target = self
            item.state = (layout.id == currentID) ? .on : .off
            sub.addItem(item)
        }

        let customLayouts = sortedCustomLayouts()
        if !customLayouts.isEmpty {
            sub.addItem(.separator())
            let customHeader = NSMenuItem(title: "Custom", action: nil, keyEquivalent: "")
            customHeader.isEnabled = false
            sub.addItem(customHeader)

            for layout in customLayouts {
                let item = NSMenuItem(
                    title: layout.name,
                    action: #selector(selectLayout(_:)),
                    keyEquivalent: ""
                )
                item.representedObject = layout
                item.target = self
                item.state = (layout.id == currentID) ? .on : .off
                sub.addItem(item)
            }
        }
        return sub
    }

    private func buildScreenLayoutsSubmenu() -> NSMenu {
        let sub = NSMenu()
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            let noneItem = NSMenuItem(title: "No displays available", action: nil, keyEquivalent: "")
            noneItem.isEnabled = false
            sub.addItem(noneItem)
            return sub
        }

        for (index, screen) in screens.enumerated() {
            let screenID = self.screenID(for: screen)
            let item = NSMenuItem(
                title: screenLayoutMenuTitle(for: screen, index: index, totalScreens: screens.count),
                action: nil,
                keyEquivalent: ""
            )
            item.submenu = buildScreenLayoutPickerSubmenu(forScreenID: screenID)
            sub.addItem(item)
        }

        return sub
    }

    private func buildScreenLayoutPickerSubmenu(forScreenID screenID: UInt32) -> NSMenu {
        let sub = NSMenu()
        let defaultLayout = controller?.currentLayout ?? .sideBySide
        let selectedLayout = controller?.layout(forScreenID: screenID) ?? defaultLayout
        let hasOverride = controller?.hasLayoutOverride(forScreenID: screenID) ?? false

        let useDefaultItem = NSMenuItem(
            title: "Use Default (\(defaultLayout.name))",
            action: #selector(selectLayoutForScreen(_:)),
            keyEquivalent: ""
        )
        useDefaultItem.target = self
        useDefaultItem.representedObject = ScreenLayoutSelection(screenID: screenID, layoutID: nil)
        useDefaultItem.state = hasOverride ? .off : .on
        sub.addItem(useDefaultItem)
        sub.addItem(.separator())

        let builtInHeader = NSMenuItem(title: "Built-in", action: nil, keyEquivalent: "")
        builtInHeader.isEnabled = false
        sub.addItem(builtInHeader)

        for layout in ZoneLayout.builtIn {
            let item = NSMenuItem(
                title: layout.name,
                action: #selector(selectLayoutForScreen(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = ScreenLayoutSelection(screenID: screenID, layoutID: layout.id)
            item.state = (hasOverride && layout.id == selectedLayout.id) ? .on : .off
            sub.addItem(item)
        }

        let customLayouts = sortedCustomLayouts()
        if !customLayouts.isEmpty {
            sub.addItem(.separator())
            let customHeader = NSMenuItem(title: "Custom", action: nil, keyEquivalent: "")
            customHeader.isEnabled = false
            sub.addItem(customHeader)

            for layout in customLayouts {
                let item = NSMenuItem(
                    title: layout.name,
                    action: #selector(selectLayoutForScreen(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = ScreenLayoutSelection(screenID: screenID, layoutID: layout.id)
                item.state = (hasOverride && layout.id == selectedLayout.id) ? .on : .off
                sub.addItem(item)
            }
        }

        return sub
    }

    private func screenLayoutMenuTitle(for screen: NSScreen, index: Int, totalScreens: Int) -> String {
        let base = screen.localizedName
        if totalScreens == 1 {
            return base
        }
        return "Display \(index + 1): \(base)"
    }

    private func screenID(for screen: NSScreen) -> UInt32 {
        if let controller {
            return controller.screenID(for: screen)
        }
        if let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return n.uint32Value
        }
        return (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) ?? 0
    }

    private func buildCustomLayoutsSubmenu() -> NSMenu {
        let sub = NSMenu()
        let customLayouts = sortedCustomLayouts()
        let isActiveLayoutCustom: Bool
        if let activeScreen = ScreenDetector.screenAtCursor {
            let activeLayoutID = controller?.layout(for: activeScreen).id
            isActiveLayoutCustom = activeLayoutID.flatMap { controller?.customLayout(withID: $0) } != nil
        } else if let activeLayoutID = controller?.currentLayout.id {
            isActiveLayoutCustom = controller?.customLayout(withID: activeLayoutID) != nil
        } else {
            isActiveLayoutCustom = false
        }

        let newItem = NSMenuItem(title: "New Custom Layout…", action: #selector(createCustomLayout), keyEquivalent: "")
        newItem.target = self
        sub.addItem(newItem)

        let editActiveItem = NSMenuItem(
            title: isActiveLayoutCustom ? "Edit Active Layout…" : "Customize Active Layout…",
            action: #selector(openLayoutEditor),
            keyEquivalent: ""
        )
        editActiveItem.target = self
        sub.addItem(editActiveItem)
        sub.addItem(.separator())

        if customLayouts.isEmpty {
            let noneItem = NSMenuItem(title: "No custom layouts yet", action: nil, keyEquivalent: "")
            noneItem.isEnabled = false
            sub.addItem(noneItem)
            return sub
        }

        for layout in customLayouts {
            let isCurrent = layout.id == controller?.currentLayout.id
            let parentItem = NSMenuItem(title: layout.name, action: nil, keyEquivalent: "")
            parentItem.state = isCurrent ? .on : .off

            let itemMenu = NSMenu()
            if isCurrent {
                let activeItem = NSMenuItem(title: "Currently Active", action: nil, keyEquivalent: "")
                activeItem.isEnabled = false
                itemMenu.addItem(activeItem)
            } else {
                let useItem = NSMenuItem(title: "Use Layout", action: #selector(useCustomLayout(_:)), keyEquivalent: "")
                useItem.target = self
                useItem.representedObject = layout.id
                itemMenu.addItem(useItem)
            }

            let editItem = NSMenuItem(title: "Edit Layout…", action: #selector(editCustomLayout(_:)), keyEquivalent: "")
            editItem.target = self
            editItem.representedObject = layout.id
            itemMenu.addItem(editItem)

            itemMenu.addItem(.separator())
            let deleteItem = NSMenuItem(title: "Delete Layout…", action: #selector(deleteCustomLayout(_:)), keyEquivalent: "")
            deleteItem.target = self
            deleteItem.representedObject = layout.id
            itemMenu.addItem(deleteItem)

            parentItem.submenu = itemMenu
            sub.addItem(parentItem)
        }
        return sub
    }

    private func sortedCustomLayouts() -> [ZoneLayout] {
        (controller?.customLayouts ?? []).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    // MARK: - Actions

    @objc private func selectLayout(_ sender: NSMenuItem) {
        guard let layout = sender.representedObject as? ZoneLayout else { return }
        controller?.setLayout(layout)
        reloadMenu()
    }

    @objc private func selectLayoutForScreen(_ sender: NSMenuItem) {
        guard let selection = sender.representedObject as? ScreenLayoutSelection else { return }
        if let layoutID = selection.layoutID {
            guard let layout = controller?.availableLayouts.first(where: { $0.id == layoutID }) else { return }
            controller?.setLayout(layout, forScreenID: selection.screenID)
        } else {
            controller?.clearLayoutOverride(forScreenID: selection.screenID)
        }
        reloadMenu()
    }

    @objc private func openAccessibilitySettings() {
        PermissionManager.openSystemSettings()
    }

    @objc private func openLayoutEditor() {
        controller?.beginLayoutEditor()
    }

    @objc private func createCustomLayout() {
        controller?.beginLayoutEditor(editingCustomLayoutID: nil, forceNewLayout: true)
    }

    @objc private func useCustomLayout(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        guard let layout = controller?.customLayout(withID: id) else { return }
        controller?.setLayout(layout)
        reloadMenu()
    }

    @objc private func editCustomLayout(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        controller?.beginLayoutEditor(editingCustomLayoutID: id)
    }

    @objc private func deleteCustomLayout(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        confirmDeleteCustomLayout(id: id)
    }

    private func confirmDeleteCustomLayout(id: UUID) {
        guard let layout = controller?.customLayout(withID: id) else { return }
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
