import Cocoa

/// Floating transparent panel showing all available keyboard shortcuts.
class ShortcutHelpPanel: NSPanel {

    init(screen: NSScreen) {
        let panelW: CGFloat = 320
        let panelH: CGFloat = 420
        let origin = NSPoint(
            x: screen.frame.midX - panelW / 2,
            y: screen.frame.midY - panelH / 2
        )
        super.init(
            contentRect: NSRect(origin: origin, size: NSSize(width: panelW, height: panelH)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar + 3
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = true

        let container = NSView(frame: NSRect(origin: .zero, size: NSSize(width: panelW, height: panelH)))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(white: 0.08, alpha: 0.88).cgColor
        container.layer?.cornerRadius = 16
        contentView = container

        buildContent(in: container)
    }

    private func buildContent(in container: NSView) {
        let scroll = NSScrollView(frame: container.bounds.insetBy(dx: 16, dy: 16))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        // Title
        let title = makeLabel("Keyboard Shortcuts", size: 16, bold: true)
        stack.addArrangedSubview(title)
        stack.setCustomSpacing(12, after: title)

        // Tool shortcuts
        let toolHeader = makeLabel("── Tools ──", size: 11, bold: true, color: .systemYellow)
        stack.addArrangedSubview(toolHeader)
        stack.setCustomSpacing(4, after: toolHeader)

        let toolShortcuts = ToolShortcutManager.shared.allBindings()
        for binding in toolShortcuts {
            let name = toolDisplayName(binding.action)
            stack.addArrangedSubview(makeRow(key: binding.key.uppercased(), desc: name))
        }

        stack.setCustomSpacing(10, after: stack.arrangedSubviews.last!)

        // Action shortcuts
        let actionHeader = makeLabel("── Actions ──", size: 11, bold: true, color: .systemYellow)
        stack.addArrangedSubview(actionHeader)
        stack.setCustomSpacing(4, after: actionHeader)

        let actions: [(key: String, desc: String)] = [
            ("⌘C", "Copy to clipboard"),
            ("⌘S", "Save to file"),
            ("⌘D", "Duplicate annotation"),
            ("⌘L", "Lock / Unlock annotation"),
            ("⌘Z", "Undo"),
            ("⇧⌘Z", "Redo"),
            ("⌘]", "Bring forward"),
            ("⌘[", "Send backward"),
            ("⌘A", "Select all → Del to clear"),
            ("⇧⌘C", "Copy annotation style"),
            ("⇧⌘V", "Paste annotation style"),
            ("⌘⌥⇡⇣", "Annotation opacity (scroll)"),
            ("⇧+Click", "Multi-select annotations"),
            ("←→↑↓", "Nudge 1px (⇧: 10px)"),
            ("⌘⇧←", "Align left"),
            ("⌘⇧→", "Align right"),
            ("⌘←→", "Center horizontally"),
            ("Tab", "Snap to window"),
            ("Enter", "Confirm / Copy"),
            ("Esc", "Cancel / Deselect"),
            ("Del", "Delete annotation"),
        ]
        for a in actions {
            stack.addArrangedSubview(makeRow(key: a.key, desc: a.desc))
        }

        stack.setCustomSpacing(10, after: stack.arrangedSubviews.last!)

        // View shortcuts
        let viewHeader = makeLabel("── View ──", size: 11, bold: true, color: .systemYellow)
        stack.addArrangedSubview(viewHeader)
        stack.setCustomSpacing(4, after: viewHeader)

        let views: [(key: String, desc: String)] = [
            ("⌘+/⌘-", "Zoom in / out"),
            ("⌘0", "Reset zoom"),
            ("?", "Toggle this help"),
        ]
        for v in views {
            stack.addArrangedSubview(makeRow(key: v.key, desc: v.desc))
        }

        let clipView = scroll.contentView
        scroll.documentView = stack

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: clipView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
        ])

        container.addSubview(scroll)
    }

    // MARK: - Helpers

    private func makeLabel(_ text: String, size: CGFloat, bold: Bool, color: NSColor = .white) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = bold ? .systemFont(ofSize: size, weight: .bold) : .systemFont(ofSize: size)
        label.textColor = color
        return label
    }

    private func makeRow(key: String, desc: String) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .firstBaseline

        let keyLabel = NSTextField(labelWithString: key)
        keyLabel.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        keyLabel.textColor = .systemOrange
        keyLabel.alignment = .right
        keyLabel.widthAnchor.constraint(equalToConstant: 56).isActive = true

        let descLabel = NSTextField(labelWithString: desc)
        descLabel.font = .systemFont(ofSize: 12)
        descLabel.textColor = NSColor(white: 0.9, alpha: 1)

        row.addArrangedSubview(keyLabel)
        row.addArrangedSubview(descLabel)
        return row
    }

    private func toolDisplayName(_ action: ToolbarButtonAction) -> String {
        switch action {
        case .tool(let tool):
            switch tool {
            case .pencil: return "Pencil"
            case .arrow: return "Arrow"
            case .line: return "Line"
            case .rectangle: return "Rectangle"
            case .text: return "Text"
            case .marker: return "Marker"
            case .number: return "Number"
            case .pixelate: return "Censor / Pixelate"
            case .colorSampler: return "Color Picker"
            case .select: return "Select & Edit"
            case .stamp: return "Stamp / Emoji"
            case .ellipse: return "Ellipse"
            case .blur: return "Blur"
            case .measure: return "Measure"
            case .loupe: return "Magnify (Loupe)"
            default: return "\(tool)"
            }
        case .detach: return "Open in Editor"
        default: return ""
        }
    }
}
