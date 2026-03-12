import AppKit

/// A single drop zone defined by a normalized rect relative to a screen's visible area.
///
/// Coordinate convention (AppKit): origin at bottom-left, y increases upward.
///   x: 0.0 = left edge,   1.0 = right edge
///   y: 0.0 = bottom edge (above Dock), 1.0 = top edge (below menu bar)
struct Zone: Identifiable, Equatable, Codable {
    let id: UUID
    let name: String
    /// Normalized rect; all values are in [0.0, 1.0].
    let normalizedRect: CGRect

    init(id: UUID = UUID(), name: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.id = id
        self.name = name
        self.normalizedRect = CGRect(x: x, y: y, width: width, height: height)
    }

    // MARK: - Coordinate helpers

    /// Returns this zone's rect in global AppKit screen coordinates,
    /// mapped onto the screen's visible frame (excluding Dock and menu bar).
    func screenRect(in visibleFrame: CGRect) -> CGRect {
        CGRect(
            x: visibleFrame.minX + normalizedRect.minX * visibleFrame.width,
            y: visibleFrame.minY + normalizedRect.minY * visibleFrame.height,
            width: normalizedRect.width * visibleFrame.width,
            height: normalizedRect.height * visibleFrame.height
        )
    }

    /// Returns this zone's rect in the local coordinate space of an overlay NSWindow
    /// whose frame equals `screen.frame`.
    func overlayViewRect(screen: NSScreen) -> CGRect {
        let sr = screenRect(in: screen.visibleFrame)
        // Subtract the screen origin so the rect is relative to the window's bottom-left.
        return CGRect(
            x: sr.minX - screen.frame.minX,
            y: sr.minY - screen.frame.minY,
            width: sr.width,
            height: sr.height
        )
    }
}
