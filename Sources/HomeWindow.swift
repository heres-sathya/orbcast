import AppKit
import AVFoundation

protocol HomeWindowDelegate: AnyObject {
    func homeStartRecording()
    func homeCameraChanged()
    func homeBubbleChanged()
    func homeOpenPermissions()
}

/// The main control panel: sources, camera bubble style, quality, and the big record button.
final class HomeWindow: NSPanel {
    weak var homeDelegate: HomeWindowDelegate?

    let recordButton = PillButton(title: "Start Recording", color: Brand.record, icon: "record.circle.fill", height: 44, fontSize: 15)
    let displayPopup = NSPopUpButton()
    let cameraPopup = NSPopUpButton()
    let micPopup = NSPopUpButton()
    let systemAudioSwitch = NSSwitch()
    let qualityPopup = NSPopUpButton()
    let countdownSwitch = NSSwitch()
    let clicksSwitch = NSSwitch()
    let shapeControl = NSSegmentedControl()
    let sizeControl = NSSegmentedControl(labels: ["S", "M", "L", "XL"], trackingMode: .selectOne, target: nil, action: nil)
    let statusLabel = makeLabel("Ready to record", size: 11.5)

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 308, height: 560),
                   styleMask: [.titled, .closable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        title = Brand.name
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        appearance = NSAppearance(named: .darkAqua)
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        buildUI()
        reloadDevices()
        if let vf = NSScreen.main?.visibleFrame {
            setFrameTopLeftPoint(NSPoint(x: vf.maxX - frame.width - 24, y: vf.maxY - 24))
        }
        NotificationCenter.default.addObserver(self, selector: #selector(syncFromPrefs), name: .prefsChanged, object: nil)
        for n in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            NotificationCenter.default.addObserver(forName: n, object: nil, queue: .main) { [weak self] _ in self?.reloadDevices() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.reloadDisplays() }
    }

    private func buildUI() {
        let bg = hudBackground()
        contentView = bg

        // Header
        let icon = NSImageView(image: NSApp.applicationIconImage ?? NSImage())
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 38).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 38).isActive = true
        let title = makeLabel(Brand.name, size: 17, weight: .bold, color: .labelColor)
        let titles = NSStackView(views: [title, statusLabel])
        titles.orientation = .vertical
        titles.alignment = .leading
        titles.spacing = 1
        let gear = IconButton("lock.shield", tint: .secondaryLabelColor, size: 28, tooltip: "Permissions")
        gear.target = self
        gear.action = #selector(openPermissions)
        let spacer = NSView()
        let header = NSStackView(views: [icon, titles, spacer, gear])
        header.alignment = .centerY
        header.spacing = 10
        header.translatesAutoresizingMaskIntoConstraints = false
        header.widthAnchor.constraint(equalToConstant: 268).isActive = true

        // Record
        recordButton.target = self
        recordButton.action = #selector(startTapped)
        recordButton.widthAnchor.constraint(equalToConstant: 268).isActive = true
        let hint = makeLabel("⌥⌘R start / stop   ·   ⌥⌘P pause", size: 10.5, color: .tertiaryLabelColor)

        // Sources
        for p in [displayPopup, cameraPopup, micPopup, qualityPopup] {
            p.controlSize = .regular
            p.target = self
        }
        displayPopup.action = #selector(displayChanged)
        cameraPopup.action = #selector(cameraChanged)
        micPopup.action = #selector(micChanged)
        qualityPopup.action = #selector(qualityChanged)
        systemAudioSwitch.target = self
        systemAudioSwitch.action = #selector(systemAudioChanged)
        countdownSwitch.target = self
        countdownSwitch.action = #selector(countdownChanged)
        clicksSwitch.target = self
        clicksSwitch.action = #selector(clicksChanged)
        for s in [systemAudioSwitch, countdownSwitch, clicksSwitch] { s.controlSize = .small }

        qualityPopup.addItems(withTitles: ["1080p · 30 fps", "1080p · 60 fps", "4K · 60 fps (HEVC)"])

        // Bubble style
        shapeControl.segmentCount = 3
        shapeControl.trackingMode = .selectOne
        for (i, s) in ["circle.fill", "square.fill", "rectangle.fill"].enumerated() {
            shapeControl.setImage(symbol(s, size: 12), forSegment: i)
            shapeControl.setToolTip(["Circle", "Rounded square", "Wide 16:9"][i], forSegment: i)
        }
        shapeControl.segmentDistribution = .fillEqually
        sizeControl.segmentDistribution = .fillEqually
        shapeControl.target = self
        shapeControl.action = #selector(shapeChanged)
        sizeControl.target = self
        sizeControl.action = #selector(sizeChanged)

        // Footer
        let folder = NSButton(title: "Recordings", image: symbol("folder", size: 12) ?? NSImage(),
                              target: self, action: #selector(openFolder))
        folder.bezelStyle = .accessoryBarAction
        folder.imagePosition = .imageLeading
        let quit = NSButton(title: "Quit", target: NSApp, action: #selector(NSApplication.terminate(_:)))
        quit.bezelStyle = .accessoryBarAction
        let fspacer = NSView()
        let footer = NSStackView(views: [folder, fspacer, quit])
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.widthAnchor.constraint(equalToConstant: 268).isActive = true

        let stack = NSStackView(views: [
            header,
            recordButton, hint,
            divider(),
            sectionHeader("Sources"),
            formRow("Screen", displayPopup),
            formRow("Camera", cameraPopup),
            formRow("Microphone", micPopup),
            formRow("System audio", systemAudioSwitch),
            divider(),
            sectionHeader("Camera bubble"),
            formRow("Shape", shapeControl, controlWidth: 140),
            formRow("Size", sizeControl, controlWidth: 140),
            divider(),
            sectionHeader("Output"),
            formRow("Quality", qualityPopup),
            formRow("3-2-1 countdown", countdownSwitch),
            formRow("Highlight clicks", clicksSwitch),
            divider(),
            footer,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(16, after: header)
        stack.setCustomSpacing(6, after: recordButton)
        stack.setCustomSpacing(14, after: hint)
        for v in stack.arrangedSubviews where v is NSBox { stack.setCustomSpacing(12, after: v) }
        pin(stack, in: bg, insets: NSEdgeInsets(top: 34, left: 20, bottom: 14, right: 20))
        syncFromPrefs()
    }

    // MARK: Devices

    func reloadDevices() {
        cameraPopup.removeAllItems()
        cameraPopup.addItem(withTitle: "No camera")
        cameraPopup.menu?.addItem(.separator())
        for c in CameraBubble.cameras() {
            cameraPopup.addItem(withTitle: c.localizedName)
            cameraPopup.lastItem?.representedObject = c.uniqueID
        }
        if !Prefs.cameraOn { cameraPopup.selectItem(at: 0) }
        else if let id = Prefs.cameraID, let item = cameraPopup.itemArray.first(where: { $0.representedObject as? String == id }) {
            cameraPopup.select(item)
        } else if cameraPopup.numberOfItems > 2 { cameraPopup.selectItem(at: 2) }

        micPopup.removeAllItems()
        micPopup.addItem(withTitle: "No microphone")
        micPopup.menu?.addItem(.separator())
        let mics = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external],
                                                    mediaType: .audio, position: .unspecified).devices
        let defaultMic = AVCaptureDevice.default(for: .audio)
        for m in mics {
            micPopup.addItem(withTitle: m.localizedName + (m.uniqueID == defaultMic?.uniqueID ? " (default)" : ""))
            micPopup.lastItem?.representedObject = m.uniqueID
        }
        if !Prefs.micOn { micPopup.selectItem(at: 0) }
        else if let id = Prefs.micID, let item = micPopup.itemArray.first(where: { $0.representedObject as? String == id }) {
            micPopup.select(item)
        } else if let item = micPopup.itemArray.first(where: { $0.representedObject as? String == defaultMic?.uniqueID }) {
            micPopup.select(item)
        } else if micPopup.numberOfItems > 2 { micPopup.selectItem(at: 2) }
        reloadDisplays()
        syncFromPrefs()
    }

    func reloadDisplays() {
        displayPopup.removeAllItems()
        for (i, s) in NSScreen.screens.enumerated() {
            let name = s.localizedName.isEmpty ? "Display \(i + 1)" : s.localizedName
            displayPopup.addItem(withTitle: name)
            displayPopup.lastItem?.tag = Int(s.displayID)
        }
        if let id = Prefs.displayID, let item = displayPopup.itemArray.first(where: { $0.tag == Int(id) }) {
            displayPopup.select(item)
        }
    }

    var selectedScreen: NSScreen {
        let id = UInt32(displayPopup.selectedItem?.tag ?? 0)
        return NSScreen.screens.first(where: { $0.displayID == id }) ?? NSScreen.main ?? NSScreen.screens[0]
    }

    // MARK: Actions

    @objc func syncFromPrefs() {
        systemAudioSwitch.state = Prefs.systemAudio ? .on : .off
        countdownSwitch.state = Prefs.countdown ? .on : .off
        clicksSwitch.state = Prefs.showCursorClicks ? .on : .off
        qualityPopup.selectItem(at: Prefs.quality)
        shapeControl.selectedSegment = Prefs.bubbleShape.rawValue
        sizeControl.selectedSegment = Prefs.bubbleSize
        if !Prefs.cameraOn, cameraPopup.numberOfItems > 0 { cameraPopup.selectItem(at: 0) }
        // Bubble style is always editable (it applies whenever the camera is shown).
        shapeControl.isEnabled = true
        sizeControl.isEnabled = true
    }

    @objc func startTapped() { homeDelegate?.homeStartRecording() }
    @objc func openPermissions() { homeDelegate?.homeOpenPermissions() }
    @objc func openFolder() { NSWorkspace.shared.open(Prefs.recordingsFolder) }

    @objc func displayChanged() { Prefs.displayID = UInt32(displayPopup.selectedItem?.tag ?? 0) }

    @objc func cameraChanged() {
        if let id = cameraPopup.selectedItem?.representedObject as? String {
            Prefs.cameraOn = true
            Prefs.cameraID = id
        } else {
            Prefs.cameraOn = false
        }
        syncFromPrefs()
        homeDelegate?.homeCameraChanged()
    }

    @objc func micChanged() {
        if let id = micPopup.selectedItem?.representedObject as? String {
            Prefs.micOn = true
            Prefs.micID = id
        } else {
            Prefs.micOn = false
        }
    }

    @objc func systemAudioChanged() { Prefs.systemAudio = systemAudioSwitch.state == .on }
    @objc func countdownChanged() { Prefs.countdown = countdownSwitch.state == .on }
    @objc func clicksChanged() { Prefs.showCursorClicks = clicksSwitch.state == .on }
    @objc func qualityChanged() { Prefs.quality = qualityPopup.indexOfSelectedItem }
    @objc func shapeChanged() {
        Prefs.bubbleShape = BubbleShape(rawValue: shapeControl.selectedSegment) ?? .circle
        homeDelegate?.homeBubbleChanged()
    }
    @objc func sizeChanged() {
        Prefs.bubbleSize = sizeControl.selectedSegment
        homeDelegate?.homeBubbleChanged()
    }
}
