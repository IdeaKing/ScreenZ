import AppKit

/// Shared visual constants for zone rendering in runtime and editor overlays.
enum ZoneVisualStyle {
    static let inactiveFill   = NSColor(white: 1.0, alpha: 0.06)
    static let inactiveBorder = NSColor(white: 1.0, alpha: 0.25)

    static let activeFill   = NSColor(red: 0.20, green: 0.50, blue: 1.00, alpha: 0.30)
    static let activeBorder = NSColor(red: 0.30, green: 0.65, blue: 1.00, alpha: 0.90)
    static let activeShadow = NSColor(red: 0.20, green: 0.50, blue: 1.00, alpha: 0.35)

    static let borderWidth: CGFloat  = 1.5
    static let cornerRadius: CGFloat = 10
    static let insetAmount: CGFloat  = 4
    static let labelFont             = NSFont.systemFont(ofSize: 12, weight: .medium)
}
