import AppKit

enum Brand {
    static let name = "Orbcast"
    static let accent = NSColor(srgbRed: 0.42, green: 0.30, blue: 0.98, alpha: 1)      // indigo
    static let pink = NSColor(srgbRed: 0.93, green: 0.29, blue: 0.60, alpha: 1)
    static let record = NSColor(srgbRed: 1.0, green: 0.23, blue: 0.31, alpha: 1)
}

func makeLabel(_ s: String, size: CGFloat = 12, weight: NSFont.Weight = .regular,
               color: NSColor = .secondaryLabelColor) -> NSTextField {
    let l = NSTextField(labelWithString: s)
    l.font = .systemFont(ofSize: size, weight: weight)
    l.textColor = color
    l.lineBreakMode = .byTruncatingTail
    return l
}

func sectionHeader(_ s: String) -> NSTextField {
    let l = makeLabel(s.uppercased(), size: 10, weight: .semibold, color: .tertiaryLabelColor)
    return l
}

/// A label-left / control-right row with fixed width.
func formRow(_ title: String, _ control: NSView, width: CGFloat = 268, controlWidth: CGFloat = 158) -> NSView {
    let l = makeLabel(title, size: 12.5, weight: .regular, color: .labelColor)
    control.translatesAutoresizingMaskIntoConstraints = false
    if !(control is NSSwitch) {
        control.widthAnchor.constraint(equalToConstant: controlWidth).isActive = true
    }
    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    let row = NSStackView(views: [l, spacer, control])
    row.orientation = .horizontal
    row.alignment = .centerY
    row.translatesAutoresizingMaskIntoConstraints = false
    row.widthAnchor.constraint(equalToConstant: width).isActive = true
    return row
}

func divider(width: CGFloat = 268) -> NSView {
    let v = NSBox()
    v.boxType = .separator
    v.translatesAutoresizingMaskIntoConstraints = false
    v.widthAnchor.constraint(equalToConstant: width).isActive = true
    return v
}

func symbol(_ name: String, size: CGFloat = 14, weight: NSFont.Weight = .semibold) -> NSImage? {
    let cfg = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
    return NSImage(systemSymbolName: name, accessibilityDescription: name)?.withSymbolConfiguration(cfg)
}

/// Big rounded, filled call-to-action button with hover feedback.
final class PillButton: NSButton {
    var fill: NSColor { didSet { updateLayer() } }
    private var hovering = false { didSet { updateLayer() } }

    private var iconName: String?

    init(title: String, color: NSColor, icon: String? = nil, height: CGFloat = 40, fontSize: CGFloat = 14) {
        fill = color
        iconName = icon
        super.init(frame: .zero)
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = height / 2
        layer?.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: height).isActive = true
        setTitle(title, fontSize: fontSize)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Icon is embedded in the title so it stays centred next to the text.
    func setTitle(_ t: String, fontSize: CGFloat = 14) {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let out = NSMutableAttributedString()
        if let iconName, let img = symbol(iconName, size: fontSize, weight: .bold) {
            let tinted = NSImage(size: img.size, flipped: false) { r in
                img.draw(in: r)
                NSColor.white.set()
                r.fill(using: .sourceAtop)
                return true
            }
            let att = NSTextAttachment()
            att.image = tinted
            att.bounds = CGRect(x: 0, y: (font.capHeight - img.size.height) / 2, width: img.size.width, height: img.size.height)
            out.append(NSAttributedString(attachment: att))
            out.append(NSAttributedString(string: "  "))
        }
        out.append(NSAttributedString(string: t))
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        out.addAttributes([.foregroundColor: NSColor.white, .font: font, .paragraphStyle: para],
                          range: NSRange(location: 0, length: out.length))
        attributedTitle = out
    }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        let c = isEnabled ? (hovering ? fill.blended(withFraction: 0.12, of: .white) ?? fill : fill)
                          : fill.withAlphaComponent(0.45)
        layer?.backgroundColor = c.cgColor
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override var isEnabled: Bool { didSet { updateLayer() } }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}

/// Round icon-only button used in the recording bar.
final class IconButton: NSButton {
    private var hovering = false { didSet { updateLayer() } }
    var hoverColor = NSColor.white.withAlphaComponent(0.14)

    init(_ sym: String, tint: NSColor = .white, size: CGFloat = 30, tooltip: String) {
        super.init(frame: .zero)
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = size / 2
        image = symbol(sym, size: 13, weight: .bold)
        imagePosition = .imageOnly
        contentTintColor = tint
        toolTip = tooltip
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: size).isActive = true
        heightAnchor.constraint(equalToConstant: size).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }

    func setSymbol(_ sym: String) { image = symbol(sym, size: 13, weight: .bold) }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() { layer?.backgroundColor = hovering ? hoverColor.cgColor : NSColor.clear.cgColor }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
}

/// Dark, blurred background used by all Orbcast windows.
func hudBackground(cornerRadius: CGFloat = 0) -> NSVisualEffectView {
    let v = NSVisualEffectView()
    v.material = .hudWindow
    v.blendingMode = .behindWindow
    v.state = .active
    // Solid dark tint so the panel looks the same over light or dark content, active or not.
    let tint = NSView(frame: .zero)
    tint.wantsLayer = true
    tint.layer?.backgroundColor = NSColor(srgbRed: 0.08, green: 0.07, blue: 0.12, alpha: 0.9).cgColor
    pin(tint, in: v)
    if cornerRadius > 0 {
        v.wantsLayer = true
        v.layer?.cornerRadius = cornerRadius
        v.layer?.cornerCurve = .continuous
        v.layer?.masksToBounds = true
    }
    return v
}

func pin(_ child: NSView, in parent: NSView, insets: NSEdgeInsets = NSEdgeInsets()) {
    child.translatesAutoresizingMaskIntoConstraints = false
    parent.addSubview(child)
    NSLayoutConstraint.activate([
        child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: insets.left),
        child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -insets.right),
        child.topAnchor.constraint(equalTo: parent.topAnchor, constant: insets.top),
        child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -insets.bottom),
    ])
}

func formatDuration(_ t: TimeInterval) -> String {
    let s = max(0, Int(t))
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
                     : String(format: "%02d:%02d", s / 60, s % 60)
}

func showAlert(_ title: String, _ text: String) {
    let a = NSAlert()
    a.messageText = title
    a.informativeText = text
    NSApp.activate(ignoringOtherApps: true)
    a.runModal()
}

extension NSScreen {
    var displayID: UInt32 {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
