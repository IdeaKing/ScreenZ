import AppKit

/// The content view of a `ZoneOverlayWindow`.
///
/// Renders each zone as a translucent rounded rectangle with a bright border.
/// The currently highlighted zone (nearest to the cursor) is drawn with higher opacity
/// to give clear visual feedback without obscuring the desktop.
final class ZoneOverlayView: NSView {

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
                dx: ZoneVisualStyle.insetAmount, dy: ZoneVisualStyle.insetAmount)
            let path = CGPath(roundedRect: viewRect,
                              cornerWidth: ZoneVisualStyle.cornerRadius,
                              cornerHeight: ZoneVisualStyle.cornerRadius,
                              transform: nil)

            ctx.saveGState()

            // Shadow for highlighted zone only
            if isHighlighted {
                ctx.setShadow(offset: .zero, blur: 16,
                              color: ZoneVisualStyle.activeShadow.cgColor)
            }

            // Fill
            ctx.setFillColor(isHighlighted
                ? ZoneVisualStyle.activeFill.cgColor
                : ZoneVisualStyle.inactiveFill.cgColor)
            ctx.addPath(path)
            ctx.fillPath()

            // Border
            ctx.setStrokeColor(isHighlighted
                ? ZoneVisualStyle.activeBorder.cgColor
                : ZoneVisualStyle.inactiveBorder.cgColor)
            ctx.setLineWidth(isHighlighted
                ? ZoneVisualStyle.borderWidth * 2
                : ZoneVisualStyle.borderWidth)
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
            .font: ZoneVisualStyle.labelFont,
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
