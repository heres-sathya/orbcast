import AppKit

// MARK: - Recording bar (floating pill shown while recording; hidden from the video)

protocol RecordingBarDelegate: AnyObject {
    func barStop()
    func barPauseResume()
    func barRestart()
    func barDiscard()
    func barToggleCamera()
}

final class RecordingBar: NSPanel {
    weak var barDelegate: RecordingBarDelegate?
    private let dot = NSView()
    private let timeLabel = NSTextField(labelWithString: "00:00")
    private let pauseButton = IconButton("pause.fill", tooltip: "Pause (⌥⌘P)")
    private let stopButton = IconButton("stop.fill", tint: Brand.record, tooltip: "Stop & save (⌥⌘R)")
    private let restartButton = IconButton("arrow.counterclockwise", tooltip: "Restart")
    private let discardButton = IconButton("trash", tooltip: "Discard recording")
    private let cameraButton = IconButton("video.fill", tooltip: "Show / hide camera")
    private let meter = LevelMeter()
    private var blink: Timer?

    init(on screen: NSScreen) {
        let size = NSSize(width: 330, height: 50)
        let vf = screen.visibleFrame
        super.init(contentRect: NSRect(x: vf.midX - size.width / 2, y: vf.minY + 24, width: size.width, height: size.height),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        appearance = NSAppearance(named: .darkAqua)

        let bg = hudBackground(cornerRadius: 25)
        contentView = bg

        dot.wantsLayer = true
        dot.layer?.backgroundColor = Brand.record.cgColor
        dot.layer?.cornerRadius = 5
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.widthAnchor.constraint(equalToConstant: 10).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 10).isActive = true

        timeLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        timeLabel.textColor = .white
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.widthAnchor.constraint(equalToConstant: 60).isActive = true

        meter.translatesAutoresizingMaskIntoConstraints = false
        meter.widthAnchor.constraint(equalToConstant: 6).isActive = true
        meter.heightAnchor.constraint(equalToConstant: 22).isActive = true
        meter.toolTip = "Microphone level"

        let sep = NSView()
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
        sep.translatesAutoresizingMaskIntoConstraints = false
        sep.widthAnchor.constraint(equalToConstant: 1).isActive = true
        sep.heightAnchor.constraint(equalToConstant: 22).isActive = true

        for (b, sel) in [(pauseButton, #selector(pauseTapped)), (stopButton, #selector(stopTapped)),
                         (restartButton, #selector(restartTapped)), (discardButton, #selector(discardTapped)),
                         (cameraButton, #selector(cameraTapped))] {
            b.target = self
            b.action = sel
        }

        let stack = NSStackView(views: [dot, timeLabel, meter, sep, stopButton, pauseButton, restartButton, cameraButton, discardButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.setCustomSpacing(10, after: dot)
        stack.setCustomSpacing(12, after: meter)
        stack.setCustomSpacing(10, after: sep)
        pin(stack, in: bg, insets: NSEdgeInsets(top: 10, left: 18, bottom: 10, right: 12))

        blink = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            guard let self, !self.isPausedUI else { return }
            self.dot.alphaValue = self.dot.alphaValue > 0.5 ? 0.25 : 1
        }
    }

    private(set) var isPausedUI = false

    func update(elapsed: TimeInterval, paused: Bool, cameraVisible: Bool) {
        timeLabel.stringValue = formatDuration(elapsed)
        if paused != isPausedUI {
            isPausedUI = paused
            pauseButton.setSymbol(paused ? "play.fill" : "pause.fill")
            pauseButton.toolTip = paused ? "Resume (⌥⌘P)" : "Pause (⌥⌘P)"
            dot.layer?.backgroundColor = (paused ? NSColor.systemYellow : Brand.record).cgColor
            dot.alphaValue = 1
        }
        cameraButton.setSymbol(cameraVisible ? "video.fill" : "video.slash.fill")
    }

    func setMicLevel(_ l: Float) { meter.level = CGFloat(l) }

    func setSaving() {
        timeLabel.stringValue = "Saving…"
        [pauseButton, stopButton, restartButton, discardButton, cameraButton].forEach { $0.isEnabled = false }
    }

    override func close() { blink?.invalidate(); super.close() }

    @objc private func stopTapped() { barDelegate?.barStop() }
    @objc private func pauseTapped() { barDelegate?.barPauseResume() }
    @objc private func restartTapped() { barDelegate?.barRestart() }
    @objc private func discardTapped() { barDelegate?.barDiscard() }
    @objc private func cameraTapped() { barDelegate?.barToggleCamera() }
}

final class LevelMeter: NSView {
    var level: CGFloat = 0 { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        let r = bounds
        NSColor.white.withAlphaComponent(0.15).setFill()
        NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3).fill()
        let h = r.height * max(0.04, min(1, level))
        let fill = NSRect(x: 0, y: 0, width: r.width, height: h)
        (level > 0.9 ? NSColor.systemRed : NSColor.systemGreen).setFill()
        NSBezierPath(roundedRect: fill, xRadius: 3, yRadius: 3).fill()
    }
}

// MARK: - 3-2-1 countdown

final class CountdownWindow: NSPanel {
    private let label = NSTextField(labelWithString: "3")
    private var timer: Timer?
    private var onDone: ((Bool) -> Void)?

    init(on screen: NSScreen) {
        let size: CGFloat = 190
        let f = screen.frame
        super.init(contentRect: NSRect(x: f.midX - size / 2, y: f.midY - size / 2, width: size, height: size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver
        hasShadow = true
        appearance = NSAppearance(named: .darkAqua)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let bg = hudBackground(cornerRadius: size / 2)
        contentView = bg
        label.font = .systemFont(ofSize: 92, weight: .bold)
        label.textColor = .white
        label.alignment = .center
        let hint = makeLabel("click to cancel", size: 11, color: .white.withAlphaComponent(0.6))
        hint.alignment = .center
        let stack = NSStackView(views: [label, hint])
        stack.orientation = .vertical
        stack.spacing = -4
        stack.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(stack)
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: bg.centerXAnchor),
                                     stack.centerYAnchor.constraint(equalTo: bg.centerYAnchor, constant: 4)])
        let click = NSClickGestureRecognizer(target: self, action: #selector(cancelTapped))
        bg.addGestureRecognizer(click)
    }

    func run(from n: Int = 3, done: @escaping (Bool) -> Void) {
        onDone = done
        var count = n
        label.stringValue = "\(count)"
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; animator().alphaValue = 1 }
        pulse()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            count -= 1
            if count > 0 {
                self.label.stringValue = "\(count)"
                self.pulse()
            } else {
                t.invalidate()
                self.finish(cancelled: false)
            }
        }
    }

    private func pulse() {
        guard let layer = label.layer ?? { label.wantsLayer = true; return label.layer }() else { return }
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = 0.2
        a.toValue = 1
        a.duration = 0.35
        layer.add(a, forKey: "pulse")
    }

    @objc private func cancelTapped() { timer?.invalidate(); finish(cancelled: true) }

    private func finish(cancelled: Bool) {
        let cb = onDone
        onDone = nil
        orderOut(nil)
        cb?(cancelled)
    }
}

// MARK: - Click highlights (transparent overlay that IS included in the recording)

final class ClickOverlay: NSPanel {
    private var monitor: Any?
    private let host = NSView()

    init(on screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        host.wantsLayer = true
        contentView = host
        setFrame(screen.frame, display: false)
    }

    func start() {
        orderFrontRegardless()
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] e in
            self?.ripple(at: NSEvent.mouseLocation, right: e.type == .rightMouseDown)
        }
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        orderOut(nil)
    }

    private func ripple(at screenPoint: NSPoint, right: Bool) {
        guard frame.contains(screenPoint), let root = host.layer else { return }
        let p = NSPoint(x: screenPoint.x - frame.minX, y: screenPoint.y - frame.minY)
        let r: CGFloat = 22
        let ring = CAShapeLayer()
        ring.path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2), transform: nil)
        ring.position = p
        let color = right ? Brand.pink : Brand.accent
        ring.fillColor = color.withAlphaComponent(0.25).cgColor
        ring.strokeColor = color.cgColor
        ring.lineWidth = 3
        root.addSublayer(ring)

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.4
        scale.toValue = 1.5
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        let g = CAAnimationGroup()
        g.animations = [scale, fade]
        g.duration = 0.55
        g.timingFunction = CAMediaTimingFunction(name: .easeOut)
        g.isRemovedOnCompletion = false
        g.fillMode = .forwards
        ring.add(g, forKey: "ripple")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { ring.removeFromSuperlayer() }
    }
}
