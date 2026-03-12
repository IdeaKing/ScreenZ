import AppKit
import CoreGraphics

/// Stateless utilities for screen detection and coordinate-system conversion.
///
/// macOS uses **two** coordinate systems that must not be confused:
///
/// | System      | Origin      | Y direction | Used by                       |
/// |-------------|-------------|-------------|-------------------------------|
/// | AppKit      | bottom-left | upward      | NSScreen, NSWindow, NSEvent   |
/// | CoreGraphics| top-left    | downward    | CGEvent, AXUIElement position |
///
/// Primary-screen height anchors the conversion between them.
enum ScreenDetector {

    // MARK: - Coordinate conversion

    /// Converts a position returned by `CGEvent.location` (CG coordinates, top-left origin)
    /// to AppKit screen coordinates (bottom-left origin).
    static func appKitPoint(fromCG cgPoint: CGPoint) -> CGPoint {
        let h = primaryScreenHeight
        return CGPoint(x: cgPoint.x, y: h - cgPoint.y)
    }

    /// Converts an AppKit screen rect's **top-left corner** to the CG position needed
    /// by `kAXPositionAttribute` (top-left origin, y downward).
    ///
    /// - Parameter screenRect: A rect in AppKit global screen coordinates.
    static func cgPosition(fromAppKitRect screenRect: CGRect) -> CGPoint {
        let h = primaryScreenHeight
        // In AppKit, maxY is the top edge; in CG, y=0 is the top.
        return CGPoint(x: screenRect.minX, y: h - screenRect.maxY)
    }

    // MARK: - Screen detection

    /// Returns the NSScreen that contains `point` (AppKit coordinates).
    static func screen(at appKitPoint: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(appKitPoint) }
    }

    /// Returns the NSScreen that currently contains the mouse cursor.
    /// `NSEvent.mouseLocation` is already in AppKit coordinates.
    static var screenAtCursor: NSScreen? {
        screen(at: NSEvent.mouseLocation)
    }

    // MARK: - Private

    private static var primaryScreenHeight: CGFloat {
        // screens[0] is always the primary display (with the menu bar).
        NSScreen.screens.first?.frame.height ?? 0
    }
}
