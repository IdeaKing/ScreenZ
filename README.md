# ScreenZ

A lightweight macOS window-snapping utility — FancyZones for macOS.

Hold **⇧ Shift** while dragging any window to see the drop-zone overlay.
Release the mouse over a highlighted zone to snap the window to that zone.

---

## Quick Start (Swift Package)

1. Build:
   ```bash
   swift build
   ```
2. Run:
   ```bash
   swift run
   ```
3. Verify ScreenZ is running from the menu bar icon and test:
   - hold **⇧ Shift**
   - drag a window
   - release over a highlighted zone

### Accessibility Permission Checklist (exact)

1. Open **System Settings → Privacy & Security → Accessibility**.
2. Enable **ScreenZ**.
3. If you launch from a host app, also enable that host:
   - `Terminal` when using `swift run`
   - `Xcode` when using Run (⌘R)
4. Fully quit ScreenZ and relaunch after changing permissions.
5. If behavior is still unclear, inspect `~/screenz-debug.log`.

### Build Distributable App (with icon)

Run:
```bash
./scripts/package_app.sh
```

This builds a universal release app, generates `AppIcon.icns` from `icon.png`,
signs the app ad-hoc, and writes:
- `dist/ScreenZ.app`
- `dist/ScreenZ.zip`

### Build macOS Installer (.pkg)

Run:
```bash
./scripts/build_installer.sh
```

This rebuilds the app bundle and creates:
- `dist/ScreenZ-installer.pkg`

The installer places `ScreenZ.app` into `/Applications`.

---

## Project Structure

```
screenz/
├── Sources/
│   ├── Models/
│   │   ├── Zone.swift           — Normalized zone rect + coordinate helpers
│   │   └── ZoneLayout.swift     — Named collections of zones; built-in layouts
│   ├── Core/
│   │   ├── PermissionManager.swift   — Accessibility permission request + alert
│   │   ├── LayoutStore.swift         — JSON persistence for custom layouts
│   │   ├── ScreenDetector.swift      — AppKit ↔ CoreGraphics coordinate conversion
│   │   ├── GlobalEventMonitor.swift  — Global mouse monitor: Shift+drag detection
│   │   └── WindowResizer.swift       — AXUIElement window move/resize
│   └── UI/
│       ├── ZoneOverlayView.swift     — NSView: draws zones; highlights hovered zone
│       ├── ZoneOverlayWindow.swift   — Transparent, non-interactive NSWindow per screen
│       ├── OverlayManager.swift      — Creates/caches overlay windows; multi-monitor aware
│       ├── LayoutEditorOverlay.swift — Dedicated full-screen editor state + interaction
│       ├── ZoneVisualStyle.swift     — Shared translucent zone styling constants
│       ├── AppController.swift       — Wires monitor → overlay → resizer
│       └── AppDelegate.swift         — @NSApplicationMain; status-bar menu
└── Resources/
    └── Info.plist                    — LSUIElement=YES, NSAccessibilityUsageDescription
```

---

## Setup: Creating the Xcode Project

### Step 1 — Create a new macOS App project

1. Open Xcode → **File › New › Project…**
2. Choose **macOS › App** and click **Next**.
3. Fill in:
   | Field | Value |
   |-------|-------|
   | Product Name | `ScreenZ` |
   | Bundle Identifier | `com.yourname.ScreenZ` |
   | Interface | **XIB** (not SwiftUI) |
   | Life Cycle | **AppKit App Delegate** |
   | Language | **Swift** |
4. Click **Next**, choose a location, and click **Create**.

### Step 2 — Remove the template files

Delete these auto-generated files (move to Trash when prompted):
- `ViewController.swift`
- `MainMenu.xib` (or `Main.storyboard`)
- The default `AppDelegate.swift` content

### Step 3 — Add the source files

Drag all files from `Sources/` into the Xcode project navigator under your target.
When prompted, tick **"Copy items if needed"** and ensure the target membership checkbox is checked.

Organize into groups (optional but recommended):
- `Models` → `Zone.swift`, `ZoneLayout.swift`
- `Core` → `PermissionManager.swift`, `ScreenDetector.swift`, `GlobalEventMonitor.swift`, `WindowResizer.swift`
- `UI` → `ZoneOverlayView.swift`, `ZoneOverlayWindow.swift`, `OverlayManager.swift`, `AppController.swift`, `AppDelegate.swift`

### Step 4 — Configure Info.plist

Replace your target's `Info.plist` with the one in `Resources/Info.plist`, or manually add:

| Key | Value |
|-----|-------|
| `LSUIElement` | `YES` (Boolean) — hides Dock icon |
| `NSAccessibilityUsageDescription` | *(the string in the provided plist)* |

To edit in Xcode: select the target → **Info** tab → expand the plist.

### Step 5 — Build Settings

| Setting | Value |
|---------|-------|
| Deployment Target | macOS 13.0+ |
| Swift Language Version | Swift 5.9+ |
| Signing | Your personal or team certificate |

### Step 6 — Request Accessibility permission

1. **Build & Run** the app once (⌘R).
2. macOS will show a system alert: _"ScreenZ wants to control this computer"_.
3. Click **Open System Settings** in the alert (or in the ScreenZ menu bar icon).
4. Navigate to **System Settings › Privacy & Security › Accessibility**.
5. Toggle **ScreenZ** to **ON**.
6. **Quit and relaunch** ScreenZ — the event tap requires a fresh process start after permission is granted.

> **Why this permission?**
> ScreenZ uses two macOS APIs that require Accessibility:
> - `NSEvent.addGlobalMonitorForEvents` to observe drag gestures while running in the background.
> - `AXUIElementSetAttributeValue` to programmatically move and resize windows.

---

## Usage

| Action | Effect |
|--------|--------|
| Hold **⇧** and drag any window | Zone overlay appears on the active screen |
| Move cursor over a zone | Zone highlights in blue |
| Release mouse over a zone | Window snaps to that zone |
| Release **⇧** before releasing mouse | Overlay dismisses; window moves freely |
| Status-bar menu › Default Layout | Choose the fallback layout used by displays without overrides |
| Status-bar menu › Screen Layouts | Assign a different layout to each connected display |
| Status-bar menu › Custom Layouts › New Custom Layout… | Create a new custom layout from the current active layout |
| Status-bar menu › Custom Layouts › Edit Active Layout… | Edit the current custom layout (or customize the active built-in layout) |
| Status-bar menu › Custom Layouts › *Layout Name* › Edit/Delete | Edit or delete any previously saved custom layout |

### Custom layout editor

The dedicated editor mode pauses normal window management and opens a full-screen transparent overlay.
- Drag on empty space to create a panel
- Drag inside a panel to move it
- Drag panel edges/corners to resize it
- Use the X/Y/W/H inspector fields for precise numeric sizing of the selected panel
- Press **Delete** (or **Fn+Delete**) to remove the selected panel
- Panels snap to display bounds and adjacent panel edges for precise alignment
- Saved layouts are serialized as JSON at `~/Library/Application Support/ScreenZ/layouts.json`

---

## Architecture Notes

### Coordinate systems

macOS uses two incompatible coordinate systems that this project carefully bridges:

```
AppKit (NSScreen, NSWindow, NSEvent)   CoreGraphics (CGEvent, AXUIElement)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Origin: bottom-left of primary screen  Origin: top-left of primary screen
Y axis: increases upward               Y axis: increases downward
```

`ScreenDetector.swift` contains the conversion functions used throughout:
- `appKitPoint(fromCG:)` — CGEvent position → NSScreen/NSWindow coordinates
- `cgPosition(fromAppKitRect:)` — AppKit zone rect → AX position for window placement

### Zone layout rendering

`ZoneOverlayView` maps each `Zone`'s `normalizedRect` → `screen.visibleFrame` → overlay-window-local rect at draw time. This means the same `Zone` values work correctly on any screen resolution and regardless of menu-bar or Dock configuration.

### Multi-monitor support

`OverlayManager` maintains a dictionary of `ZoneOverlayWindow` instances keyed by `NSScreenNumber`. Only the overlay on the screen containing the cursor is shown during a drag. If the cursor moves across a display boundary, the old overlay fades out and the new one fades in.

### Layout editor state

`AppController` now has a dedicated layout-editor mode that:
- pauses the global drag monitor while editing
- renders a single full-screen interactive overlay on the active display
- captures all mouse input inside the editor window so underlying apps cannot be interacted with
- serializes panel geometry to JSON-backed custom layouts consumed by the runtime layout menu

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Overlay doesn't appear | Accessibility not granted | See Step 6 above |
| Overlay still doesn't appear after enabling ScreenZ | Launch host app (Terminal/Xcode) is not trusted | Enable the host app in Accessibility and relaunch ScreenZ |
| Window doesn't snap | Accessibility not granted | Same |
| Overlay appears but window doesn't move | Some apps (browser, sandboxed apps) resist AX | Expected; not all windows are AX-resizable |
| App crashes on launch | Missing Info.plist keys | Verify `LSUIElement` and `NSAccessibilityUsageDescription` are present |
| Event tap disabled warning in console | macOS timed out the tap (rare) | The tap auto-re-enables; if persistent, relaunch |
