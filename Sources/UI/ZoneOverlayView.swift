import AppKit

/// The content view of a `ZoneOverlayWindow`.
///
/// Renders each zone as a translucent rounded rectangle with a bright border.
/// The currently highlighted zone (nearest to the cursor) is drawn with higher opacity
/// to give clear visual feedback without obscuring the desktop.
final class ZoneOverlayView: NSView {

    // MARK: - Appearance constants

    private enum Style {
        /// Default zone fill — very subtle so the desktop remains readable.
        static let inactiveFill  = NSColor(white: 1.0, alpha: 0.06)
        /// Default zone border.
        static let inactiveBorder = NSColor(white: 1.0, alpha: 0.25)
        /// Highlighted zone fill — clearly visible without being opaque.
        static let activeFill    = NSColor(red: 0.20, green: 0.50, blue: 1.00, alpha: 0.30)
        /// Highlighted zone border — accent-coloured and more prominent.
        static let activeBorder  = NSColor(red: 0.30, green: 0.65, blue: 1.00, alpha: 0.90)
        /// Highlighted zone shadow colour.
        static let activeShadow  = NSColor(red: 0.20, green: 0.50, blue: 1.00, alpha: 0.35)

        static let borderWidth: CGFloat   = 1.5
        static let cornerRadius: CGFloat  = 10
        static let insetAmount: CGFloat   = 4   // Padding so adjacent zone borders don't overlap
        static let labelFont              = NSFont.systemFont(ofSize: 12, weight: .medium)
    }

    // MARK: - State

    /// The screen this overlay covers. Used for coordinate mapping.
    var screen: NSScreen

    /// The layout whose zones are rendered.
    var layout: ZoneLayout { didSet { needsDisplay = true } }

    /// The ID of the zone currently under the cursor, or `nil` for none.
    var highlightedZoneID: UUID? { didSet { needsDisplay = true } }

    // MARK: - Init

    init(screen: NSScreen, layout: ZoneLayout) {
        self.screen = screen
        self.layout = layout
        // The view fills the overlay window, which is sized to screen.frame.
        super.init(frame: CGRect(origin: .zero, size: screen.frame.size))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(screen:layout:)") }

    // MARK: - Drawing

    override var isFlipped: Bool { false }   // Standard AppKit convention (origin = bottom-left)
    override var isOpaque: Bool  { false }   // Transparent background

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        for zone in layout.zones {
            let isHighlighted = (zone.id == highlightedZoneID)
            let viewRect = zone.overlayViewRect(screen: screen).insetBy(
                dx: Style.insetAmount, dy: Style.insetAmount)
            let path = CGPath(roundedRect: viewRect,
                              cornerWidth: Style.cornerRadius,
                              cornerHeight: Style.cornerRadius,
                              transform: nil)

            ctx.saveGState()

            // Shadow for highlighted zone only
            if isHighlighted {
                ctx.setShadow(offset: .zero, blur: 16,
                              color: Style.activeShadow.cgColor)
            }

            // Fill
            ctx.setFillColor(isHighlighted
                ? Style.activeFill.cgColor
                : Style.inactiveFill.cgColor)
            ctx.addPath(path)
            ctx.fillPath()

            // Border
            ctx.setStrokeColor(isHighlighted
                ? Style.activeBorder.cgColor
                : Style.inactiveBorder.cgColor)
            ctx.setLineWidth(isHighlighted
                ? Style.borderWidth * 2
                : Style.borderWidth)
            ctx.addPath(path)
            ctx.strokePath()

            ctx.restoreGState()

            // Zone name label (only when highlighted to avoid clutter)
            if isHighlighted {
                drawLabel(zone.name, in: viewRect)
            }
        }
    }

    // MARK: - Label rendering

    private func drawLabel(_ text: String, in rect: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Style.labelFont,
            .foregroundColor: NSColor.white,
        ]
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let size = attributedString.size()
        let labelRect = CGRect(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        attributedString.draw(in: labelRect)
    }
}
