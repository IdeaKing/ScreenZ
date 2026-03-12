import AppKit

private struct ZoneDraft: Identifiable {
    let id: UUID
    var name: String
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat

    init(id: UUID = UUID(), name: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.id = id
        self.name = name
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    var normalizedRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    var isValid: Bool {
        x >= 0 &&
        y >= 0 &&
        width > 0 &&
        height > 0 &&
        x + width <= 1 &&
        y + height <= 1
    }

    var clampedRect: CGRect {
        let clampedX = min(max(x, 0), 1)
        let clampedY = min(max(y, 0), 1)
        let clampedW = min(max(width, 0), 1 - clampedX)
        let clampedH = min(max(height, 0), 1 - clampedY)
        return CGRect(x: clampedX, y: clampedY, width: clampedW, height: clampedH)
    }
}

private final class ZoneDraftRowView: NSView, NSTextFieldDelegate {
    var onDraftChanged: ((ZoneDraft) -> Void)?
    var onRemove: (() -> Void)?

    private let draftID: UUID
    private let zoneLabel = NSTextField(labelWithString: "")
    private let nameField = NSTextField(string: "")
    private let xField = NSTextField(string: "")
    private let yField = NSTextField(string: "")
    private let wField = NSTextField(string: "")
    private let hField = NSTextField(string: "")

    init(draft: ZoneDraft, index: Int) {
        self.draftID = draft.id
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setup(draft: draft, index: index)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(draft:index:)") }

    func updateIndex(_ index: Int) {
        zoneLabel.stringValue = "Zone \(index)"
    }

    private func setup(draft: ZoneDraft, index: Int) {
        zoneLabel.stringValue = "Zone \(index)"
        zoneLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        zoneLabel.textColor = .secondaryLabelColor
        zoneLabel.alignment = .right
        zoneLabel.translatesAutoresizingMaskIntoConstraints = false

        nameField.stringValue = draft.name
        nameField.placeholderString = "Name"
        nameField.delegate = self

        [xField, yField, wField, hField].forEach {
            $0.alignment = .right
            $0.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            $0.delegate = self
            $0.placeholderString = "0.00"
        }
        xField.stringValue = Self.format(draft.x)
        yField.stringValue = Self.format(draft.y)
        wField.stringValue = Self.format(draft.width)
        hField.stringValue = Self.format(draft.height)

        let removeButton = NSButton(title: "Remove", target: self, action: #selector(removeTapped))
        removeButton.bezelStyle = .rounded

        let stack = NSStackView(views: [
            zoneLabel,
            nameField,
            xField,
            yField,
            wField,
            hField,
            removeButton,
        ])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fill
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        NSLayoutConstraint.activate([
            zoneLabel.widthAnchor.constraint(equalToConstant: 56),
            nameField.widthAnchor.constraint(equalToConstant: 170),
            xField.widthAnchor.constraint(equalToConstant: 72),
            yField.widthAnchor.constraint(equalToConstant: 72),
            wField.widthAnchor.constraint(equalToConstant: 72),
            hField.widthAnchor.constraint(equalToConstant: 72),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    func controlTextDidChange(_ obj: Notification) {
        emitDraft()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        emitDraft()
    }

    @objc private func removeTapped() {
        onRemove?()
    }

    private func emitDraft() {
        let draft = ZoneDraft(
            id: draftID,
            name: trimmed(nameField.stringValue, fallback: "Zone"),
            x: parse(xField.stringValue),
            y: parse(yField.stringValue),
            width: parse(wField.stringValue),
            height: parse(hField.stringValue)
        )
        onDraftChanged?(draft)
    }

    private func parse(_ string: String) -> CGFloat {
        let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        return CGFloat(Double(normalized) ?? 0)
    }

    private func trimmed(_ string: String, fallback: String) -> String {
        let t = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? fallback : t
    }

    private static func format(_ value: CGFloat) -> String {
        String(format: "%.2f", value)
    }
}

private final class LayoutPreviewView: NSView {
    var drafts: [ZoneDraft] = [] { didSet { needsDisplay = true } }

    override var isFlipped: Bool { false }
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let canvas = bounds.insetBy(dx: 12, dy: 12)
        let bg = NSBezierPath(roundedRect: canvas, xRadius: 10, yRadius: 10)
        NSColor(calibratedWhite: 0.10, alpha: 0.95).setFill()
        bg.fill()
        NSColor(calibratedWhite: 1, alpha: 0.15).setStroke()
        bg.lineWidth = 1
        bg.stroke()

        for (idx, draft) in drafts.enumerated() {
            let rectN = draft.clampedRect
            let rect = CGRect(
                x: canvas.minX + rectN.minX * canvas.width,
                y: canvas.minY + rectN.minY * canvas.height,
                width: rectN.width * canvas.width,
                height: rectN.height * canvas.height
            ).insetBy(dx: 2, dy: 2)

            let hue = CGFloat((idx * 47) % 360) / 360
            let fill = NSColor(calibratedHue: hue, saturation: 0.55, brightness: 1.0, alpha: draft.isValid ? 0.34 : 0.16)
            let stroke = draft.isValid
                ? NSColor(calibratedHue: hue, saturation: 0.72, brightness: 1.0, alpha: 0.92)
                : NSColor.systemRed

            let path = CGPath(
                roundedRect: rect,
                cornerWidth: 8,
                cornerHeight: 8,
                transform: nil
            )
            ctx.addPath(path)
            ctx.setFillColor(fill.cgColor)
            ctx.fillPath()

            ctx.addPath(path)
            ctx.setStrokeColor(stroke.cgColor)
            ctx.setLineWidth(2)
            ctx.strokePath()

            let label = NSAttributedString(
                string: draft.name,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                    .foregroundColor: NSColor.white,
                ]
            )
            let size = label.size()
            label.draw(in: CGRect(
                x: rect.midX - size.width / 2,
                y: rect.midY - size.height / 2,
                width: size.width,
                height: size.height
            ))
        }
    }
}

final class CustomLayoutEditorWindowController: NSWindowController {
    var onLayoutSaved: ((ZoneLayout) -> Void)?
    var onLayoutDeleted: ((UUID) -> Void)?

    private let layoutStore: LayoutStore

    private var currentCustomLayoutID: UUID?
    private var drafts: [ZoneDraft] = []

    private let layoutPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let nameField = NSTextField(string: "")
    private let rowsContainer = NSStackView()
    private let previewView = LayoutPreviewView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let deleteButton = NSButton(title: "Delete", target: nil, action: nil)

    init(layoutStore: LayoutStore = .shared) {
        self.layoutStore = layoutStore
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Custom Layout Editor"
        window.minSize = NSSize(width: 840, height: 520)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
        loadDraftForNewLayout()
        rebuildPicker(selecting: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(layoutStore:)") }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - UI

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ])

        let title = NSTextField(labelWithString: "Create and edit your own window-zone arrangements")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        root.addArrangedSubview(title)

        let help = NSTextField(labelWithString: "Use normalized values: x,y,width,height within 0...1. Top menu instantly uses saved layouts.")
        help.textColor = .secondaryLabelColor
        help.font = .systemFont(ofSize: 12)
        root.addArrangedSubview(help)

        let topRow = NSStackView()
        topRow.orientation = .horizontal
        topRow.alignment = .centerY
        topRow.spacing = 8

        layoutPicker.target = self
        layoutPicker.action = #selector(layoutSelectionChanged)
        layoutPicker.widthAnchor.constraint(equalToConstant: 260).isActive = true

        let newButton = NSButton(title: "New Layout", target: self, action: #selector(newLayoutTapped))
        newButton.bezelStyle = .rounded

        let nameLabel = NSTextField(labelWithString: "Name:")
        nameLabel.textColor = .secondaryLabelColor

        nameField.placeholderString = "Layout name"
        nameField.widthAnchor.constraint(equalToConstant: 280).isActive = true

        topRow.addArrangedSubview(NSTextField(labelWithString: "Custom Layout:"))
        topRow.addArrangedSubview(layoutPicker)
        topRow.addArrangedSubview(newButton)
        topRow.addArrangedSubview(nameLabel)
        topRow.addArrangedSubview(nameField)
        root.addArrangedSubview(topRow)

        let editorRow = NSStackView()
        editorRow.orientation = .horizontal
        editorRow.alignment = .top
        editorRow.distribution = .fillProportionally
        editorRow.spacing = 14
        editorRow.translatesAutoresizingMaskIntoConstraints = false

        previewView.translatesAutoresizingMaskIntoConstraints = false
        previewView.wantsLayer = true
        previewView.layer?.cornerRadius = 10
        previewView.widthAnchor.constraint(equalToConstant: 380).isActive = true
        previewView.heightAnchor.constraint(greaterThanOrEqualToConstant: 380).isActive = true

        let rightPane = NSStackView()
        rightPane.orientation = .vertical
        rightPane.alignment = .leading
        rightPane.spacing = 8
        rightPane.translatesAutoresizingMaskIntoConstraints = false

        let columnsHeader = NSTextField(labelWithString: "Zone   Name                     x       y       width   height")
        columnsHeader.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        columnsHeader.textColor = .secondaryLabelColor
        rightPane.addArrangedSubview(columnsHeader)

        rowsContainer.orientation = .vertical
        rowsContainer.alignment = .leading
        rowsContainer.spacing = 6
        rowsContainer.translatesAutoresizingMaskIntoConstraints = true
        rowsContainer.frame = NSRect(x: 0, y: 0, width: 540, height: 1)

        let scroll = NSScrollView()
        scroll.borderType = .bezelBorder
        scroll.hasVerticalScroller = true
        scroll.documentView = rowsContainer
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.widthAnchor.constraint(equalToConstant: 560).isActive = true
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 380).isActive = true

        rightPane.addArrangedSubview(scroll)

        let rowButtons = NSStackView()
        rowButtons.orientation = .horizontal
        rowButtons.spacing = 8
        let addZoneButton = NSButton(title: "Add Zone", target: self, action: #selector(addZoneTapped))
        addZoneButton.bezelStyle = .rounded
        rowButtons.addArrangedSubview(addZoneButton)
        rightPane.addArrangedSubview(rowButtons)

        editorRow.addArrangedSubview(previewView)
        editorRow.addArrangedSubview(rightPane)
        root.addArrangedSubview(editorRow)

        let bottomRow = NSStackView()
        bottomRow.orientation = .horizontal
        bottomRow.alignment = .centerY
        bottomRow.spacing = 8

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let saveButton = NSButton(title: "Save Layout", target: self, action: #selector(saveTapped))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"

        deleteButton.target = self
        deleteButton.action = #selector(deleteTapped)
        deleteButton.title = "Delete"
        deleteButton.bezelStyle = .rounded

        let closeButton = NSButton(title: "Close", target: self, action: #selector(closeTapped))
        closeButton.bezelStyle = .rounded

        bottomRow.addArrangedSubview(statusLabel)
        bottomRow.addArrangedSubview(NSView())
        bottomRow.addArrangedSubview(deleteButton)
        bottomRow.addArrangedSubview(saveButton)
        bottomRow.addArrangedSubview(closeButton)
        root.addArrangedSubview(bottomRow)
    }

    // MARK: - Actions

    @objc private func layoutSelectionChanged() {
        let idx = layoutPicker.indexOfSelectedItem
        if idx <= 0 {
            loadDraftForNewLayout()
            return
        }
        guard let idString = layoutPicker.selectedItem?.representedObject as? String,
              let id = UUID(uuidString: idString),
              let layout = layoutStore.customLayouts.first(where: { $0.id == id })
        else {
            loadDraftForNewLayout()
            return
        }
        loadDraft(from: layout)
    }

    @objc private func newLayoutTapped() {
        loadDraftForNewLayout()
        rebuildPicker(selecting: nil)
    }

    @objc private func addZoneTapped() {
        let index = drafts.count + 1
        let newZone = ZoneDraft(
            name: "Zone \(index)",
            x: 0,
            y: 0,
            width: 1,
            height: 1
        )
        drafts.append(newZone)
        rebuildRows()
        setStatus("Added Zone \(index).", isError: false)
    }

    @objc private func saveTapped() {
        let layoutName = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !layoutName.isEmpty else {
            setStatus("Enter a layout name before saving.", isError: true)
            return
        }
        guard !drafts.isEmpty else {
            setStatus("Add at least one zone.", isError: true)
            return
        }
        guard let zones = makeValidatedZones() else {
            return
        }

        let layoutID = currentCustomLayoutID ?? UUID()
        let layout = ZoneLayout(id: layoutID, name: layoutName, zones: zones)
        if let onLayoutSaved {
            onLayoutSaved(layout)
        } else {
            layoutStore.upsertCustomLayout(layout)
        }

        currentCustomLayoutID = layoutID
        rebuildPicker(selecting: layoutID)
        setStatus("Saved layout '\(layoutName)'.", isError: false)
    }

    @objc private func deleteTapped() {
        guard let id = currentCustomLayoutID else {
            setStatus("Select a saved custom layout to delete.", isError: true)
            return
        }
        if let onLayoutDeleted {
            onLayoutDeleted(id)
        } else {
            layoutStore.removeCustomLayout(id: id)
        }
        loadDraftForNewLayout()
        rebuildPicker(selecting: nil)
        setStatus("Deleted custom layout.", isError: false)
    }

    @objc private func closeTapped() {
        window?.close()
    }

    // MARK: - Draft/Rows

    private func loadDraftForNewLayout() {
        currentCustomLayoutID = nil
        nameField.stringValue = ""
        drafts = [
            ZoneDraft(name: "Main", x: 0, y: 0, width: 1, height: 1),
        ]
        rebuildRows()
        setStatus("Editing a new custom layout.", isError: false)
    }

    private func loadDraft(from layout: ZoneLayout) {
        currentCustomLayoutID = layout.id
        nameField.stringValue = layout.name
        drafts = layout.zones.enumerated().map { idx, zone in
            ZoneDraft(
                id: zone.id,
                name: zone.name.isEmpty ? "Zone \(idx + 1)" : zone.name,
                x: zone.normalizedRect.minX,
                y: zone.normalizedRect.minY,
                width: zone.normalizedRect.width,
                height: zone.normalizedRect.height
            )
        }
        if drafts.isEmpty {
            drafts = [ZoneDraft(name: "Main", x: 0, y: 0, width: 1, height: 1)]
        }
        rebuildRows()
        setStatus("Loaded '\(layout.name)'.", isError: false)
    }

    private func rebuildRows() {
        rowsContainer.arrangedSubviews.forEach {
            rowsContainer.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        for (idx, draft) in drafts.enumerated() {
            let row = ZoneDraftRowView(draft: draft, index: idx + 1)
            row.onDraftChanged = { [weak self] changed in
                guard let self else { return }
                guard let index = self.drafts.firstIndex(where: { $0.id == changed.id }) else { return }
                self.drafts[index] = changed
                self.refreshPreview()
            }
            row.onRemove = { [weak self] in
                guard let self else { return }
                self.drafts.removeAll { $0.id == draft.id }
                self.rebuildRows()
                self.setStatus("Removed zone.", isError: false)
            }
            rowsContainer.addArrangedSubview(row)
        }

        rowsContainer.needsLayout = true
        rowsContainer.layoutSubtreeIfNeeded()
        let fitting = rowsContainer.fittingSize
        rowsContainer.frame = NSRect(
            x: 0,
            y: 0,
            width: max(540, fitting.width),
            height: max(1, fitting.height)
        )
        refreshPreview()
        deleteButton.isEnabled = (currentCustomLayoutID != nil)
    }

    private func refreshPreview() {
        previewView.drafts = drafts
    }

    private func makeValidatedZones() -> [Zone]? {
        for (idx, draft) in drafts.enumerated() where !draft.isValid {
            setStatus(
                "Zone \(idx + 1) has invalid bounds. Use x,y,width,height in 0...1 and keep x+width,y+height <= 1.",
                isError: true
            )
            return nil
        }
        return drafts.enumerated().map { idx, draft in
            Zone(
                id: draft.id,
                name: draft.name.isEmpty ? "Zone \(idx + 1)" : draft.name,
                x: draft.x,
                y: draft.y,
                width: draft.width,
                height: draft.height
            )
        }
    }

    // MARK: - Picker

    private func rebuildPicker(selecting selectedID: UUID?) {
        let custom = layoutStore.customLayouts.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        layoutPicker.removeAllItems()
        layoutPicker.addItem(withTitle: "New Layout")
        layoutPicker.lastItem?.representedObject = nil

        for layout in custom {
            layoutPicker.addItem(withTitle: layout.name)
            layoutPicker.lastItem?.representedObject = layout.id.uuidString
        }

        if let selectedID,
           let index = custom.firstIndex(where: { $0.id == selectedID }) {
            layoutPicker.selectItem(at: index + 1)
        } else {
            layoutPicker.selectItem(at: 0)
        }
    }

    // MARK: - Status

    private func setStatus(_ message: String, isError: Bool) {
        statusLabel.stringValue = message
        statusLabel.textColor = isError ? .systemRed : .secondaryLabelColor
    }
}
