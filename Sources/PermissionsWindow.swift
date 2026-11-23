import AppKit
import AVFoundation

/// First-run onboarding: walks through Camera, Microphone and Screen Recording permissions.
final class PermissionsWindow: NSWindow {
    private struct Row { let status: NSTextField; let button: NSButton }
    private var rows: [String: Row] = [:]
    private var timer: Timer?
    private var screenRequested = false
    private let relaunchNote = makeLabel("", size: 11.5, color: Brand.pink)

    static var allGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .video) == .authorized
            && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            && CGPreflightScreenCaptureAccess()
    }

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 460, height: 430),
                   styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true
        appearance = NSAppearance(named: .darkAqua)
        isReleasedWhenClosed = false
        level = .floating

        let bg = hudBackground()
        contentView = bg

        let icon = NSImageView(image: NSApp.applicationIconImage ?? NSImage())
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 64).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 64).isActive = true
        let title = makeLabel("Welcome to \(Brand.name)", size: 20, weight: .bold, color: .labelColor)
        let sub = makeLabel("Three quick permissions and you're ready to record demos.", size: 12.5)

        let cam = makeRow(key: "camera", sym: "video.fill", title: "Camera", detail: "Shows you in the floating bubble")
        let mic = makeRow(key: "mic", sym: "mic.fill", title: "Microphone", detail: "Records your voice-over")
        let scr = makeRow(key: "screen", sym: "rectangle.dashed.badge.record", title: "Screen Recording",
                          detail: "Captures your screen")

        let done = PillButton(title: "Start using \(Brand.name)", color: Brand.accent, height: 38, fontSize: 13.5)
        done.target = self
        done.action = #selector(doneTapped)
        done.widthAnchor.constraint(equalToConstant: 400).isActive = true

        let stack = NSStackView(views: [icon, title, sub, cam, mic, scr, relaunchNote, done])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.setCustomSpacing(4, after: title)
        stack.setCustomSpacing(20, after: sub)
        pin(stack, in: bg, insets: NSEdgeInsets(top: 36, left: 30, bottom: 26, right: 30))
        center()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
    }

    private func makeRow(key: String, sym: String, title: String, detail: String) -> NSView {
        let iv = NSImageView(image: symbol(sym, size: 16) ?? NSImage())
        iv.contentTintColor = Brand.accent
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.widthAnchor.constraint(equalToConstant: 28).isActive = true
        let t = makeLabel(title, size: 13, weight: .semibold, color: .labelColor)
        let d = makeLabel(detail, size: 11.5)
        let texts = NSStackView(views: [t, d])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 1
        let status = makeLabel("", size: 12, weight: .semibold, color: .systemGreen)
        let button = NSButton(title: "Allow", target: self, action: #selector(allowTapped(_:)))
        button.bezelStyle = .rounded
        button.identifier = NSUserInterfaceItemIdentifier(key)
        let spacer = NSView()
        let row = NSStackView(views: [iv, texts, spacer, status, button])
        row.alignment = .centerY
        row.spacing = 10
        row.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        row.wantsLayer = true
        row.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        row.layer?.cornerRadius = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: 400).isActive = true
        rows[key] = Row(status: status, button: button)
        return row
    }

    private func refresh() {
        func set(_ key: String, granted: Bool, buttonTitle: String) {
            guard let r = rows[key] else { return }
            r.status.stringValue = granted ? "✓ Allowed" : ""
            r.button.isHidden = granted
            r.button.title = buttonTitle
        }
        let cam = AVCaptureDevice.authorizationStatus(for: .video)
        let mic = AVCaptureDevice.authorizationStatus(for: .audio)
        set("camera", granted: cam == .authorized, buttonTitle: cam == .notDetermined ? "Allow" : "Open Settings")
        set("mic", granted: mic == .authorized, buttonTitle: mic == .notDetermined ? "Allow" : "Open Settings")
        let scr = CGPreflightScreenCaptureAccess()
        set("screen", granted: scr, buttonTitle: screenRequested ? "Relaunch" : "Allow")
        relaunchNote.stringValue = (!scr && screenRequested)
            ? "After enabling Orbcast in Screen Recording settings, click Relaunch." : ""
    }

    @objc private func allowTapped(_ sender: NSButton) {
        let key = sender.identifier?.rawValue ?? ""
        func settings(_ pane: String) {
            if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
                NSWorkspace.shared.open(u)
            }
        }
        switch key {
        case "camera":
            if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
                AVCaptureDevice.requestAccess(for: .video) { _ in }
            } else { settings("Privacy_Camera") }
        case "mic":
            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                AVCaptureDevice.requestAccess(for: .audio) { _ in }
            } else { settings("Privacy_Microphone") }
        case "screen":
            if screenRequested {
                relaunch()
            } else {
                screenRequested = true
                if !CGRequestScreenCaptureAccess() { settings("Privacy_ScreenCapture") }
            }
        default: break
        }
        refresh()
    }

    private func relaunch() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 0.6; open \"\(Bundle.main.bundlePath)\""]
        try? p.run()
        NSApp.terminate(nil)
    }

    @objc private func doneTapped() {
        UserDefaults.standard.set(true, forKey: "onboarded")
        close()
    }

    override func close() { timer?.invalidate(); super.close() }
}
