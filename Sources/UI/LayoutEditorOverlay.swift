import AppKit

enum LayoutEditorResult {
    case cancelled
    case saved(ZoneLayout)
}

final class LayoutEditorOverlayController: NSObject {
    private let screen: NSScreen
    private let initialLayout: ZoneLayout?
    private let completion: (LayoutEditorResult) -> Void
    private var window: LayoutEditorOverlayWindow?
    private var isFinishing = false

    init(
        screen: NSScreen,
        initialLayout: ZoneLayout?,
        completion: @escaping (LayoutEditorResult) -> Void
    ) {
        self.screen = screen
        self.initialLayout = initialLayout
        self.completion = completion
        super.init()
    }

    func start() {
        guard window == nil else { return }

        let window = LayoutEditorOverlayWindow(screen: screen, initialLayout: initialLayout)
        window.onCancel = { [weak self] in
            self?.finish(.cancelled)
        }
        window.onSave = { [weak self] layout in
            self?.finish(.saved(layout))
        }
        self.window = window
        window.present()
    }

    func stop() {
        guard let closingWindow = window else { return }
        window = nil
        closingWindow.onCancel = nil
        closingWindow.onSave = nil
        closingWindow.close()
    }

    private func finish(_ result: LayoutEditorResult) {
        guard !isFinishing else { return }
        isFinishing = true

        let closingWindow = window
        window = nil

        // Close after the current UI event unwinds to avoid lifetime races.
        DispatchQueue.main.async { [weak self] in
            closingWindow?.onCancel = nil
            closingWindow?.onSave = nil
            closingWindow?.close()
            self?.completion(result)
            self?.isFinishing = false
        }
    }
}

private final class LayoutEditorOverlayWindow: NSWindow {
    var onSave: ((ZoneLayout) -> Void)?
    var onCancel: (() -> Void)?

    private let canvasView: LayoutEditorCanvasView
    private let layoutNameField = NSTextField(string: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let layoutID: UUID

    init(screen: NSScreen, initialLayout: ZoneLayout?) {
        self.canvasView = LayoutEditorCanvasView(screen: screen)
        self.layoutID = initialLayout?.id ?? UUID()

        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 2)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = false
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        animationBehavior = .none
        // Keep lifecycle under ARC; avoid close-time self-release races.
        isReleasedWhenClosed = false

        let root = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.clear.cgColor
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView = root

        canvasView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(canvasView)
        NSLayoutConstraint.activate([
            canvasView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            canvasView.topAnchor.constraint(equalTo: root.topAnchor),
            canvasView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        setupHUD(in: root)

        if let initialLayout {
            layoutNameField.stringValue = initialLayout.name
            canvasView.load(layout: initialLayout)
        } else {
            layoutNameField.stringValue = "Custom Layout"
        }
        refreshStatus()
    }

    func present() {
        setFrame(frame, display: true)
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func setupHUD(in root: NSView) {
        let hud = NSVisualEffectView()
        hud.material = .hudWindow
        hud.blendingMode = .withinWindow
        hud.state = .active
        hud.wantsLayer = true
        hud.layer?.cornerRadius = 12
        hud.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(hud)

        let titleLabel = NSTextField(labelWithString: "Layout Editor Mode")
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .white

        let closeButton = NSButton(title: "×", target: self, action: #selector(cancelTapped))
        closeButton.bezelStyle = .rounded
        closeButton.font = .systemFont(ofSize: 14, weight: .bold)
        closeButton.contentTintColor = .white
        closeButton.toolTip = "Close Layout Editor"
        closeButton.widthAnchor.constraint(equalToConstant: 28).isActive = true
        closeButton.heightAnchor.constraint(equalToConstant: 24).isActive = true

        let helpLabel = NSTextField(labelWithString: "Drag on empty space to create panels. Drag inside to move. Drag edges/corners to resize. Panels snap to each other.")
        helpLabel.font = .systemFont(ofSize: 11, weight: .regular)
        helpLabel.textColor = .secondaryLabelColor
        helpLabel.lineBreakMode = .byTruncatingTail

        layoutNameField.placeholderString = "Layout name"
        layoutNameField.target = self
        layoutNameField.action = #selector(layoutNameChanged)
        layoutNameField.font = .systemFont(ofSize: 12, weight: .medium)

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancelButton.bezelStyle = .rounded

        let clearButton = NSButton(title: "Clear Panels", target: self, action: #selector(clearTapped))
        clearButton.bezelStyle = .rounded

        let saveButton = NSButton(title: "Save Layout", target: self, action: #selector(saveTapped))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"

        statusLabel.font = .systemFont(ofSize: 11, weight: .regular)
        statusLabel.textColor = .secondaryLabelColor

        let buttonRow = NSStackView(views: [cancelButton, clearButton, saveButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8

        let fieldRow = NSStackView(views: [NSTextField(labelWithString: "Name"), layoutNameField, buttonRow])
        fieldRow.orientation = .horizontal
        fieldRow.alignment = .centerY
        fieldRow.spacing = 8
        fieldRow.distribution = .fill
        layoutNameField.widthAnchor.constraint(equalToConstant: 260).isActive = true

        let titleRow = NSStackView(views: [titleLabel, NSView(), closeButton])
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 8

        let stack = NSStackView(views: [titleRow, helpLabel, fieldRow, statusLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        hud.addSubview(stack)

        NSLayoutConstraint.activate([
            hud.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            hud.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            hud.widthAnchor.constraint(equalToConstant: 760),
            stack.leadingAnchor.constraint(equalTo: hud.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: hud.trailingAnchor),
            stack.topAnchor.constraint(equalTo: hud.topAnchor),
            stack.bottomAnchor.constraint(equalTo: hud.bottomAnchor),
        ])

        canvasView.eventExclusionRectsProvider = { [weak hud] in
            guard let hud else { return [] }
            return [hud.frame]
        }
        canvasView.onPanelsChanged = { [weak self] in self?.refreshStatus() }
    }

    private func refreshStatus() {
        let count = canvasView.panelCount
        statusLabel.stringValue = count == 0
            ? "Create at least one panel before saving."
            : "\(count) panel\(count == 1 ? "" : "s") configured."
    }

    @objc private func layoutNameChanged() {
        let trimmed = layoutNameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            layoutNameField.stringValue = "Custom Layout"
        }
    }

    @objc private func clearTapped() {
        canvasView.removeAllPanels()
        refreshStatus()
    }

    @objc private func cancelTapped() {
        ScreenZLog.write("[LayoutEditor] cancel tapped")
        let callback = onCancel
        DispatchQueue.main.async {
            callback?()
        }
    }

    @objc private func saveTapped() {
        let name = layoutNameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = name.isEmpty ? "Custom Layout" : name
        guard let layout = canvasView.makeLayout(name: finalName, layoutID: layoutID) else {
            statusLabel.stringValue = "Cannot save an empty layout."
            statusLabel.textColor = .systemRed
            return
        }
        ScreenZLog.write("[LayoutEditor] save tapped zones=\(layout.zones.count)")
        statusLabel.textColor = .secondaryLabelColor
        let callback = onSave
        DispatchQueue.main.async {
            callback?(layout)
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        let _ = sender
        onCancel?()
    }
}

private final class LayoutEditorCanvasView: NSView {
    private struct Panel: Identifiable {
        let id: UUID
        var name: String
        var frame: CGRect
    }

    private struct ResizeEdges: OptionSet {
        let rawValue: Int
        static let left   = ResizeEdges(rawValue: 1 << 0)
        static let right  = ResizeEdges(rawValue: 1 << 1)
        static let top    = ResizeEdges(rawValue: 1 << 2)
        static let bottom = ResizeEdges(rawValue: 1 << 3)
    }

    private enum Interaction {
        case creating(panelID: UUID, start: CGPoint)
        case moving(panelID: UUID, pointerOffset: CGPoint)
        case resizing(panelID: UUID, initialFrame: CGRect, start: CGPoint, edges: ResizeEdges)
    }

    var onPanelsChanged: (() -> Void)?
    var eventExclusionRectsProvider: (() -> [CGRect])?

    private let screen: NSScreen
    private var panels: [Panel] = []
    private var selectedPanelID: UUID?
    private var interaction: Interaction?

    private let minPanelSize: CGFloat = 48
    private let hitMargin: CGFloat = 8
    private let snapDistance: CGFloat = 10

    init(screen: NSScreen) {
        self.screen = screen
        super.init(frame: CGRect(origin: .zero, size: screen.frame.size))
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(screen:)") }

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }
    override var isFlipped: Bool { false }

    var panelCount: Int { panels.count }

    func removeAllPanels() {
        panels.removeAll()
        selectedPanelID = nil
        interaction = nil
        needsDisplay = true
        onPanelsChanged?()
    }

    func load(layout: ZoneLayout) {
        let workArea = workAreaRect
        panels = layout.zones.enumerated().map { idx, zone in
            let nr = zone.normalizedRect
            let frame = CGRect(
                x: workArea.minX + nr.minX * workArea.width,
                y: workArea.minY + nr.minY * workArea.height,
                width: nr.width * workArea.width,
                height: nr.height * workArea.height
            ).standardized
            return Panel(
                id: zone.id,
                name: zone.name.isEmpty ? "Zone \(idx + 1)" : zone.name,
                frame: frame
            )
        }
        selectedPanelID = panels.last?.id
        needsDisplay = true
        onPanelsChanged?()
    }

    func makeLayout(name: String, layoutID: UUID) -> ZoneLayout? {
        guard !panels.isEmpty else { return nil }
        let workArea = workAreaRect
        let zones = panels.enumerated().map { idx, panel in
            let frame = clampedPanelFrame(panel.frame)
            let nr = CGRect(
                x: (frame.minX - workArea.minX) / workArea.width,
                y: (frame.minY - workArea.minY) / workArea.height,
                width: frame.width / workArea.width,
                height: frame.height / workArea.height
            )
            return Zone(
                id: panel.id,
                name: panel.name.isEmpty ? "Zone \(idx + 1)" : panel.name,
                x: nr.minX,
                y: nr.minY,
                width: nr.width,
                height: nr.height
            )
        }
        return ZoneLayout(id: layoutID, name: name, zones: zones)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        ctx.setFillColor(NSColor.black.withAlphaComponent(0.12).cgColor)
        ctx.fill(bounds)

        drawWorkArea(in: ctx)

        for panel in panels {
            draw(panel: panel, in: ctx, highlighted: panel.id == selectedPanelID)
        }
    }

    private func drawWorkArea(in ctx: CGContext) {
        let work = workAreaRect
        let path = CGPath(roundedRect: work, cornerWidth: 12, cornerHeight: 12, transform: nil)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.08).cgColor)
        ctx.addPath(path)
        ctx.fillPath()

        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.22).cgColor)
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: [6, 4])
        ctx.addPath(path)
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])
    }

    private func draw(panel: Panel, in ctx: CGContext, highlighted: Bool) {
        let rect = panel.frame.insetBy(dx: ZoneVisualStyle.insetAmount, dy: ZoneVisualStyle.insetAmount)
        let path = CGPath(
            roundedRect: rect,
            cornerWidth: ZoneVisualStyle.cornerRadius,
            cornerHeight: ZoneVisualStyle.cornerRadius,
            transform: nil
        )

        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 16, color: ZoneVisualStyle.activeShadow.cgColor)
        ctx.setFillColor(ZoneVisualStyle.activeFill.cgColor)
        ctx.addPath(path)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.setStrokeColor(ZoneVisualStyle.activeBorder.cgColor)
        ctx.setLineWidth(highlighted ? ZoneVisualStyle.borderWidth * 2 : ZoneVisualStyle.borderWidth)
        ctx.addPath(path)
        ctx.strokePath()

        let label = NSAttributedString(
            string: panel.name,
            attributes: [
                .font: ZoneVisualStyle.labelFont,
                .foregroundColor: NSColor.white,
            ]
        )
        let size = label.size()
        let labelRect = CGRect(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        label.draw(in: labelRect)
    }

    // MARK: - Mouse interaction

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if eventExclusionRectsProvider?().contains(where: { $0.contains(point) }) == true {
            return
        }

        guard workAreaRect.contains(point) else {
            interaction = nil
            return
        }

        if let hit = hitTestPanel(at: point) {
            selectedPanelID = hit.id
            bringPanelToFront(id: hit.id)
            if !hit.resizeEdges.isEmpty {
                if let frame = panelFrame(id: hit.id) {
                    interaction = .resizing(panelID: hit.id, initialFrame: frame, start: point, edges: hit.resizeEdges)
                }
            } else if let frame = panelFrame(id: hit.id) {
                interaction = .moving(
                    panelID: hit.id,
                    pointerOffset: CGPoint(x: point.x - frame.minX, y: point.y - frame.minY)
                )
            }
        } else {
            let panelID = UUID()
            selectedPanelID = panelID
            panels.append(Panel(id: panelID, name: "Zone \(panels.count + 1)", frame: CGRect(origin: point, size: .zero)))
            interaction = .creating(panelID: panelID, start: point)
            onPanelsChanged?()
        }

        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let interaction else { return }

        let point = clampToWorkArea(convert(event.locationInWindow, from: nil))
        switch interaction {
        case let .creating(panelID, start):
            let raw = CGRect(
                x: min(start.x, point.x),
                y: min(start.y, point.y),
                width: abs(point.x - start.x),
                height: abs(point.y - start.y)
            )
            let snapped = snappedRectForResize(raw, edges: [.left, .right, .top, .bottom], excluding: panelID)
            updatePanel(id: panelID) { panel in panel.frame = clampedPanelFrame(snapped) }

        case let .moving(panelID, pointerOffset):
            guard let original = panelFrame(id: panelID) else { return }
            var candidate = original
            candidate.origin = CGPoint(x: point.x - pointerOffset.x, y: point.y - pointerOffset.y)
            candidate = clampedMoveRect(candidate)
            candidate = snappedRectForMove(candidate, excluding: panelID)
            updatePanel(id: panelID) { panel in panel.frame = clampedMoveRect(candidate) }

        case let .resizing(panelID, initialFrame, start, edges):
            let dx = point.x - start.x
            let dy = point.y - start.y
            var candidate = initialFrame
            if edges.contains(.left) { candidate.origin.x += dx; candidate.size.width -= dx }
            if edges.contains(.right) { candidate.size.width += dx }
            if edges.contains(.bottom) { candidate.origin.y += dy; candidate.size.height -= dy }
            if edges.contains(.top) { candidate.size.height += dy }

            candidate = enforceMinSize(candidate, edges: edges)
            candidate = clampedResizeRect(candidate, edges: edges)
            candidate = snappedRectForResize(candidate, edges: edges, excluding: panelID)
            candidate = clampedResizeRect(candidate, edges: edges)
            updatePanel(id: panelID) { panel in panel.frame = candidate }
        }

        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let _ = event
        defer {
            interaction = nil
            needsDisplay = true
        }

        if case let .creating(panelID, _) = interaction,
           let frame = panelFrame(id: panelID),
           (frame.width < minPanelSize || frame.height < minPanelSize) {
            panels.removeAll { $0.id == panelID }
            if selectedPanelID == panelID { selectedPanelID = nil }
            onPanelsChanged?()
        }
    }

    // MARK: - Hit testing

    private struct HitResult {
        let id: UUID
        let resizeEdges: ResizeEdges
    }

    private func hitTestPanel(at point: CGPoint) -> HitResult? {
        for panel in panels.reversed() {
            let frame = panel.frame
            let padded = frame.insetBy(dx: -hitMargin, dy: -hitMargin)
            guard padded.contains(point) else { continue }

            var edges: ResizeEdges = []
            if abs(point.x - frame.minX) <= hitMargin { edges.insert(.left) }
            if abs(point.x - frame.maxX) <= hitMargin { edges.insert(.right) }
            if abs(point.y - frame.minY) <= hitMargin { edges.insert(.bottom) }
            if abs(point.y - frame.maxY) <= hitMargin { edges.insert(.top) }

            if !frame.contains(point) && edges.isEmpty { continue }
            return HitResult(id: panel.id, resizeEdges: edges)
        }
        return nil
    }

    private func bringPanelToFront(id: UUID) {
        guard let idx = panels.firstIndex(where: { $0.id == id }) else { return }
        let panel = panels.remove(at: idx)
        panels.append(panel)
    }

    // MARK: - Geometry

    private var workAreaRect: CGRect {
        CGRect(
            x: screen.visibleFrame.minX - screen.frame.minX,
            y: screen.visibleFrame.minY - screen.frame.minY,
            width: screen.visibleFrame.width,
            height: screen.visibleFrame.height
        )
    }

    private func clampToWorkArea(_ point: CGPoint) -> CGPoint {
        let work = workAreaRect
        return CGPoint(
            x: min(max(point.x, work.minX), work.maxX),
            y: min(max(point.y, work.minY), work.maxY)
        )
    }

    private func clampedPanelFrame(_ frame: CGRect) -> CGRect {
        let work = workAreaRect
        var rect = frame.standardized
        rect.size.width = min(rect.width, work.width)
        rect.size.height = min(rect.height, work.height)
        rect.origin.x = min(max(rect.minX, work.minX), work.maxX - rect.width)
        rect.origin.y = min(max(rect.minY, work.minY), work.maxY - rect.height)
        return rect
    }

    private func clampedMoveRect(_ frame: CGRect) -> CGRect {
        clampedPanelFrame(frame)
    }

    private func clampedResizeRect(_ frame: CGRect, edges: ResizeEdges) -> CGRect {
        var rect = frame.standardized
        let work = workAreaRect

        if edges.contains(.left) {
            rect.origin.x = max(rect.minX, work.minX)
            rect.size.width = min(max(rect.width, minPanelSize), work.maxX - rect.minX)
        }
        if edges.contains(.right) {
            rect.size.width = min(max(rect.width, minPanelSize), work.maxX - rect.minX)
        }
        if edges.contains(.bottom) {
            rect.origin.y = max(rect.minY, work.minY)
            rect.size.height = min(max(rect.height, minPanelSize), work.maxY - rect.minY)
        }
        if edges.contains(.top) {
            rect.size.height = min(max(rect.height, minPanelSize), work.maxY - rect.minY)
        }

        return clampedPanelFrame(rect)
    }

    private func enforceMinSize(_ frame: CGRect, edges: ResizeEdges) -> CGRect {
        var rect = frame.standardized
        if rect.width < minPanelSize {
            if edges.contains(.left) {
                rect.origin.x -= (minPanelSize - rect.width)
            }
            rect.size.width = minPanelSize
        }
        if rect.height < minPanelSize {
            if edges.contains(.bottom) {
                rect.origin.y -= (minPanelSize - rect.height)
            }
            rect.size.height = minPanelSize
        }
        return rect
    }

    // MARK: - Snapping

    private func snappedRectForMove(_ frame: CGRect, excluding panelID: UUID) -> CGRect {
        var rect = frame
        let xTargets = xSnapTargets(excluding: panelID)
        let yTargets = ySnapTargets(excluding: panelID)

        rect.origin.x = snappedOriginCoordinate(
            defaultOrigin: rect.minX,
            minEdge: rect.minX,
            maxEdge: rect.maxX,
            size: rect.width,
            targets: xTargets
        )
        rect.origin.y = snappedOriginCoordinate(
            defaultOrigin: rect.minY,
            minEdge: rect.minY,
            maxEdge: rect.maxY,
            size: rect.height,
            targets: yTargets
        )

        return rect
    }

    private func snappedRectForResize(_ frame: CGRect, edges: ResizeEdges, excluding panelID: UUID) -> CGRect {
        var minX = frame.minX
        var maxX = frame.maxX
        var minY = frame.minY
        var maxY = frame.maxY
        let xTargets = xSnapTargets(excluding: panelID)
        let yTargets = ySnapTargets(excluding: panelID)

        if edges.contains(.left), let t = nearestTarget(to: minX, in: xTargets) { minX = t }
        if edges.contains(.right), let t = nearestTarget(to: maxX, in: xTargets) { maxX = t }
        if edges.contains(.bottom), let t = nearestTarget(to: minY, in: yTargets) { minY = t }
        if edges.contains(.top), let t = nearestTarget(to: maxY, in: yTargets) { maxY = t }

        return CGRect(
            x: min(minX, maxX),
            y: min(minY, maxY),
            width: abs(maxX - minX),
            height: abs(maxY - minY)
        )
    }

    private func snappedOriginCoordinate(
        defaultOrigin: CGFloat,
        minEdge: CGFloat,
        maxEdge: CGFloat,
        size: CGFloat,
        targets: [CGFloat]
    ) -> CGFloat {
        var bestOrigin = defaultOrigin
        var bestDistance = snapDistance + 1

        for target in targets {
            let leftDistance = abs(minEdge - target)
            if leftDistance <= snapDistance, leftDistance < bestDistance {
                bestDistance = leftDistance
                bestOrigin = target
            }

            let rightDistance = abs(maxEdge - target)
            if rightDistance <= snapDistance, rightDistance < bestDistance {
                bestDistance = rightDistance
                bestOrigin = target - size
            }
        }

        return bestOrigin
    }

    private func nearestTarget(to edge: CGFloat, in targets: [CGFloat]) -> CGFloat? {
        var nearest: CGFloat?
        var nearestDistance = snapDistance + 1

        for target in targets {
            let distance = abs(edge - target)
            if distance <= snapDistance, distance < nearestDistance {
                nearestDistance = distance
                nearest = target
            }
        }
        return nearest
    }

    private func xSnapTargets(excluding panelID: UUID) -> [CGFloat] {
        let work = workAreaRect
        var targets: [CGFloat] = [work.minX, work.maxX]
        for panel in panels where panel.id != panelID {
            targets.append(panel.frame.minX)
            targets.append(panel.frame.maxX)
        }
        return targets
    }

    private func ySnapTargets(excluding panelID: UUID) -> [CGFloat] {
        let work = workAreaRect
        var targets: [CGFloat] = [work.minY, work.maxY]
        for panel in panels where panel.id != panelID {
            targets.append(panel.frame.minY)
            targets.append(panel.frame.maxY)
        }
        return targets
    }

    // MARK: - Panel helpers

    private func panelFrame(id: UUID) -> CGRect? {
        panels.first(where: { $0.id == id })?.frame
    }

    private func updatePanel(id: UUID, mutate: (inout Panel) -> Void) {
        guard let idx = panels.firstIndex(where: { $0.id == id }) else { return }
        mutate(&panels[idx])
    }
}
