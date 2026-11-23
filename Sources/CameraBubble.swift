import AppKit
import AVFoundation

/// The floating webcam bubble. It is a real on-screen window, so it gets baked into the screen recording.
final class BubbleView: NSView {
    let preview: AVCaptureVideoPreviewLayer
    var shape: BubbleShape = .circle { didSet { needsLayout = true } }
    var menuProvider: (() -> NSMenu)?
    private let placeholder = NSImageView()

    init(session: AVCaptureSession) {
        preview = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 3
        layer?.borderColor = NSColor.white.withAlphaComponent(0.95).cgColor
        layer?.backgroundColor = NSColor(white: 0.12, alpha: 1).cgColor
        preview.videoGravity = .resizeAspectFill
        layer?.addSublayer(preview)

        placeholder.image = symbol("video.slash.fill", size: 28)
        placeholder.contentTintColor = .white.withAlphaComponent(0.5)
        placeholder.isHidden = true
        addSubview(placeholder)
        toolTip = "Drag to move · Right-click for shape & size"
    }
    required init?(coder: NSCoder) { fatalError() }

    func setPlaceholder(_ on: Bool) { placeholder.isHidden = !on }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        preview.frame = bounds
        layer?.cornerRadius = shape == .circle ? min(bounds.width, bounds.height) / 2 : 26
        CATransaction.commit()
        placeholder.frame = bounds
    }

    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func menu(for event: NSEvent) -> NSMenu? { menuProvider?() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
}

final class CameraBubble: NSPanel {
    static let baseSizes: [CGFloat] = [130, 190, 270, 370]
    let session = AVCaptureSession()
    let bubbleView: BubbleView
    private let sessionQueue = DispatchQueue(label: "orbcast.camera")
    private var currentInput: AVCaptureDeviceInput?
    private var currentDeviceID: String?

    var shape: BubbleShape = Prefs.bubbleShape { didSet { bubbleView.shape = shape; applySize(animate: true) } }
    var sizeIndex: Int = Prefs.bubbleSize { didSet { applySize(animate: true) } }

    init() {
        bubbleView = BubbleView(session: session)
        let vf = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        super.init(contentRect: NSRect(x: vf.minX + 40, y: vf.minY + 40, width: 190, height: 190),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = bubbleView
        bubbleView.shape = shape
        applySize(animate: false)
    }

    override var canBecomeKey: Bool { false }

    func dimensions() -> NSSize {
        let s = Self.baseSizes[max(0, min(sizeIndex, Self.baseSizes.count - 1))]
        switch shape {
        case .circle, .rounded: return NSSize(width: s, height: s)
        case .wide: return NSSize(width: (s * 1.45).rounded(), height: (s * 1.45 * 9 / 16).rounded())
        }
    }

    func applySize(animate: Bool) {
        let size = dimensions()
        var f = frame
        let center = NSPoint(x: f.midX, y: f.midY)
        f.size = size
        f.origin = NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
        if let vf = screen?.visibleFrame {   // keep it on screen
            f.origin.x = min(max(f.origin.x, vf.minX + 8), vf.maxX - size.width - 8)
            f.origin.y = min(max(f.origin.y, vf.minY + 8), vf.maxY - size.height - 8)
        }
        setFrame(f, display: true, animate: animate)
    }

    /// Moves the bubble to the bottom-left of `target` if it isn't already on it.
    func ensureOn(screen target: NSScreen) {
        if let s = screen, s.displayID == target.displayID { return }
        let vf = target.visibleFrame
        setFrameOrigin(NSPoint(x: vf.minX + 40, y: vf.minY + 40))
    }

    static func cameras() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
                                         mediaType: .video, position: .unspecified).devices
    }

    func show(deviceID: String?) {
        orderFrontRegardless()
        AVCaptureDevice.requestAccess(for: .video) { ok in
            DispatchQueue.main.async {
                guard ok else { self.bubbleView.setPlaceholder(true); return }
                self.useCamera(deviceID)
            }
        }
    }

    func hide() {
        orderOut(nil)
        sessionQueue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    private func useCamera(_ id: String?) {
        let device = id.flatMap { AVCaptureDevice(uniqueID: $0) }
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(for: .video)
        guard let device else { bubbleView.setPlaceholder(true); return }
        bubbleView.setPlaceholder(false)
        sessionQueue.async {
            if self.currentDeviceID != device.uniqueID {
                self.session.beginConfiguration()
                if let old = self.currentInput { self.session.removeInput(old) }
                self.session.sessionPreset = .high
                if let input = try? AVCaptureDeviceInput(device: device), self.session.canAddInput(input) {
                    self.session.addInput(input)
                    self.currentInput = input
                    self.currentDeviceID = device.uniqueID
                }
                self.session.commitConfiguration()
            }
            if !self.session.isRunning { self.session.startRunning() }
            DispatchQueue.main.async {
                if let c = self.bubbleView.preview.connection, c.isVideoMirroringSupported {
                    c.automaticallyAdjustsVideoMirroring = false
                    c.isVideoMirrored = true
                }
            }
        }
    }
}
