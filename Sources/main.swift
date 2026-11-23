import AppKit
import AVFoundation
import Carbon.HIToolbox

// MARK: - Global hotkeys (Carbon; no Accessibility permission needed)

enum HotKeys {
    static var handlers: [UInt32: () -> Void] = [:]
    static var refs: [EventHotKeyRef?] = []
    private static var installed = false

    static func register(id: UInt32, keyCode: Int, modifiers: Int, _ handler: @escaping () -> Void) {
        if !installed {
            installed = true
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var hk = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
                let id = hk.id
                DispatchQueue.main.async { HotKeys.handlers[id]?() }
                return noErr
            }, 1, &spec, nil, nil)
        }
        handlers[id] = handler
        var ref: EventHotKeyRef?
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), EventHotKeyID(signature: OSType(0x46524D43), id: id),
                            GetApplicationEventTarget(), 0, &ref)
        refs.append(ref)
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, HomeWindowDelegate, RecordingBarDelegate, NSMenuDelegate {
    let bubble = CameraBubble()
    let recorder = Recorder()
    var home: HomeWindow!
    var bar: RecordingBar?
    var countdown: CountdownWindow?
    var clicks: ClickOverlay?
    var permissions: PermissionsWindow?
    var reviews: [ReviewWindow] = []
    var statusItem: NSStatusItem!
    var tick: Timer?
    var busy = false

    func applicationDidFinishLaunching(_ n: Notification) {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let img = NSImage(contentsOf: iconURL) { NSApp.applicationIconImage = img }
        buildMainMenu()
        buildStatusItem()

        home = HomeWindow()
        home.homeDelegate = self
        home.makeKeyAndOrderFront(nil)

        bubble.bubbleView.menuProvider = { [weak self] in self?.bubbleMenu() ?? NSMenu() }
        if Prefs.cameraOn { bubble.show(deviceID: Prefs.cameraID) }
        home.reloadDevices()

        recorder.onUnexpectedStop = { [weak self] error in self?.recordingFailed(error) }
        recorder.onMicLevel = { [weak self] l in self?.bar?.setMicLevel(l) }

        let mods = cmdKey | optionKey
        HotKeys.register(id: 1, keyCode: kVK_ANSI_R, modifiers: mods) { [weak self] in self?.toggleRecording() }
        HotKeys.register(id: 2, keyCode: kVK_ANSI_P, modifiers: mods) { [weak self] in self?.barPauseResume() }

        if !PermissionsWindow.allGranted || !UserDefaults.standard.bool(forKey: "onboarded") {
            showPermissions()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if recorder.state == .idle && !busy { home.makeKeyAndOrderFront(nil) }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard recorder.state != .idle else { return .terminateNow }
        Task { @MainActor in
            if let url = await recorder.stop() { NSLog("Saved \(url.path)") }
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    // MARK: Menus

    func buildMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About \(Brand.name)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(withTitle: "Permissions…", action: #selector(showPermissions), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide \(Brand.name)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit \(Brand.name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let recItem = NSMenuItem()
        let rec = NSMenu(title: "Record")
        rec.addItem(withTitle: "Start / Stop Recording  (⌥⌘R)", action: #selector(toggleRecording), keyEquivalent: "")
        rec.addItem(withTitle: "Pause / Resume  (⌥⌘P)", action: #selector(barPauseResume), keyEquivalent: "")
        rec.addItem(.separator())
        rec.addItem(withTitle: "Show Control Panel", action: #selector(showHome), keyEquivalent: "1")
        rec.addItem(withTitle: "Open Recordings Folder", action: #selector(openFolder), keyEquivalent: "o")
        recItem.submenu = rec
        main.addItem(recItem)

        let winItem = NSMenuItem()
        let win = NSMenu(title: "Window")
        win.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        win.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        winItem.submenu = win
        main.addItem(winItem)
        NSApp.windowsMenu = win
        NSApp.mainMenu = main
    }

    func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = symbol("record.circle", size: 14)
        statusItem.button?.imagePosition = .imageLeading
        let m = NSMenu()
        m.delegate = self
        statusItem.menu = m
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        switch recorder.state {
        case .idle:
            menu.addItem(withTitle: "Start Recording", action: #selector(toggleRecording), keyEquivalent: "")
        case .recording, .paused:
            menu.addItem(withTitle: "Stop & Save", action: #selector(toggleRecording), keyEquivalent: "")
            menu.addItem(withTitle: recorder.state == .paused ? "Resume" : "Pause", action: #selector(barPauseResume), keyEquivalent: "")
            menu.addItem(withTitle: "Discard", action: #selector(barDiscard), keyEquivalent: "")
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: bubble.isVisible ? "Hide Camera" : "Show Camera", action: #selector(barToggleCamera), keyEquivalent: "")
        menu.addItem(withTitle: "Show Control Panel", action: #selector(showHome), keyEquivalent: "")
        menu.addItem(withTitle: "Open Recordings Folder", action: #selector(openFolder), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit \(Brand.name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        for item in menu.items where item.target == nil && item.action != #selector(NSApplication.terminate(_:)) {
            item.target = self
        }
    }

    func bubbleMenu() -> NSMenu {
        let m = NSMenu()
        for (i, name) in ["Circle", "Rounded square", "Wide (16:9)"].enumerated() {
            let it = NSMenuItem(title: name, action: #selector(bubbleShapeItem(_:)), keyEquivalent: "")
            it.tag = i
            it.target = self
            it.state = Prefs.bubbleShape.rawValue == i ? .on : .off
            m.addItem(it)
        }
        m.addItem(.separator())
        for (i, name) in ["Small", "Medium", "Large", "Extra large"].enumerated() {
            let it = NSMenuItem(title: name, action: #selector(bubbleSizeItem(_:)), keyEquivalent: "")
            it.tag = i
            it.target = self
            it.state = Prefs.bubbleSize == i ? .on : .off
            m.addItem(it)
        }
        m.addItem(.separator())
        let hide = NSMenuItem(title: "Hide Camera", action: #selector(barToggleCamera), keyEquivalent: "")
        hide.target = self
        m.addItem(hide)
        return m
    }

    @objc func bubbleShapeItem(_ sender: NSMenuItem) {
        Prefs.bubbleShape = BubbleShape(rawValue: sender.tag) ?? .circle
        homeBubbleChanged()
        NotificationCenter.default.post(name: .prefsChanged, object: nil)
    }

    @objc func bubbleSizeItem(_ sender: NSMenuItem) {
        Prefs.bubbleSize = sender.tag
        homeBubbleChanged()
        NotificationCenter.default.post(name: .prefsChanged, object: nil)
    }

    @objc func showHome() {
        guard recorder.state == .idle else { return }
        home.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func openFolder() { NSWorkspace.shared.open(Prefs.recordingsFolder) }

    @objc func showPermissions() {
        if permissions == nil { permissions = PermissionsWindow() }
        permissions?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: HomeWindowDelegate

    func homeStartRecording() { toggleRecording() }
    func homeOpenPermissions() { showPermissions() }

    func homeCameraChanged() {
        if Prefs.cameraOn { bubble.show(deviceID: Prefs.cameraID) } else { bubble.hide() }
    }

    func homeBubbleChanged() {
        bubble.shape = Prefs.bubbleShape
        bubble.sizeIndex = Prefs.bubbleSize
    }

    // MARK: Recording flow

    @objc func toggleRecording() {
        if busy { return }
        switch recorder.state {
        case .idle: beginCountdown()
        case .recording, .paused: barStop()
        }
    }

    private func beginCountdown() {
        guard CGPreflightScreenCaptureAccess() else {
            showPermissions()
            return
        }
        busy = true
        let screen = home.selectedScreen
        home.orderOut(nil)
        if bubble.isVisible { bubble.ensureOn(screen: screen) }
        guard Prefs.countdown else { startRecording(on: screen); return }
        let c = CountdownWindow(on: screen)
        countdown = c
        c.run { [weak self] cancelled in
            guard let self else { return }
            self.countdown = nil
            if cancelled {
                self.busy = false
                self.home.makeKeyAndOrderFront(nil)
            } else {
                self.startRecording(on: screen)
            }
        }
    }

    private func startRecording(on screen: NSScreen) {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let url = Prefs.recordingsFolder.appendingPathComponent("\(Brand.name) \(fmt.string(from: Date())).mov")

        // Always include the bubble (even if hidden now) so toggling the camera mid-recording shows up.
        var include: [Int] = [bubble.windowNumber]
        if Prefs.showCursorClicks {
            let overlay = ClickOverlay(on: screen)
            overlay.start()
            clicks = overlay
            include.append(overlay.windowNumber)
        }
        let opts = RecordingOptions(displayID: screen.displayID, micOn: Prefs.micOn, micID: Prefs.micID,
                                    systemAudio: Prefs.systemAudio, quality: Prefs.quality,
                                    includedWindowNumbers: include)
        Task { @MainActor in
            do {
                try await recorder.start(opts, to: url)
                let b = RecordingBar(on: screen)
                b.barDelegate = self
                b.orderFrontRegardless()
                bar = b
                busy = false
                tick = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.refreshTick() }
                refreshTick()
            } catch {
                busy = false
                cleanupRecordingUI()
                home.makeKeyAndOrderFront(nil)
                showAlert("Couldn't start recording",
                          "\(error.localizedDescription)\n\nCheck that \(Brand.name) is allowed under System Settings → Privacy & Security → Screen & System Audio Recording.")
            }
        }
    }

    private func refreshTick() {
        let t = formatDuration(recorder.elapsed)
        bar?.update(elapsed: recorder.elapsed, paused: recorder.state == .paused, cameraVisible: bubble.isVisible)
        statusItem.button?.title = recorder.state == .idle ? "" : " " + t
        statusItem.button?.image = symbol(recorder.state == .paused ? "pause.circle.fill" : "record.circle.fill", size: 14)
        statusItem.button?.contentTintColor = recorder.state == .recording ? Brand.record : nil
    }

    private func cleanupRecordingUI() {
        tick?.invalidate()
        tick = nil
        bar?.close()
        bar = nil
        clicks?.stop()
        clicks = nil
        statusItem.button?.title = ""
        statusItem.button?.image = symbol("record.circle", size: 14)
        statusItem.button?.contentTintColor = nil
    }

    private func recordingFailed(_ error: Error) {
        guard recorder.state != .idle else { return }
        Task { @MainActor in
            let url = await recorder.stop()
            cleanupRecordingUI()
            if let url { openReview(url) } else { home.makeKeyAndOrderFront(nil) }
            showAlert("Recording stopped", error.localizedDescription)
        }
    }

    private func openReview(_ url: URL) {
        let r = ReviewWindow(url: url)
        r.onClose = { [weak self] w in
            self?.reviews.removeAll { $0 === w }
            if self?.recorder.state == .idle { self?.home.orderFront(nil) }
        }
        reviews.append(r)
        r.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: RecordingBarDelegate

    @objc func barStop() {
        guard recorder.state != .idle, !busy else { return }
        busy = true
        bar?.setSaving()
        tick?.invalidate()
        Task { @MainActor in
            let url = await recorder.stop()
            cleanupRecordingUI()
            busy = false
            if let url {
                openReview(url)
            } else {
                home.makeKeyAndOrderFront(nil)
                showAlert("Nothing was recorded", "The recording was too short or the screen didn't change.")
            }
        }
    }

    @objc func barPauseResume() {
        switch recorder.state {
        case .recording: recorder.pause()
        case .paused: recorder.resume()
        case .idle: return
        }
        refreshTick()
    }

    @objc func barRestart() {
        guard recorder.state != .idle, !busy else { return }
        busy = true
        Task { @MainActor in
            await recorder.cancel()
            cleanupRecordingUI()
            busy = false
            beginCountdown()
        }
    }

    @objc func barDiscard() {
        guard recorder.state != .idle, !busy else { return }
        busy = true
        Task { @MainActor in
            await recorder.cancel()
            cleanupRecordingUI()
            busy = false
            home.makeKeyAndOrderFront(nil)
        }
    }

    @objc func barToggleCamera() {
        // Keep the saved setting in sync with what's on screen, recording or not.
        if bubble.isVisible {
            bubble.hide()
            Prefs.cameraOn = false
        } else {
            bubble.show(deviceID: Prefs.cameraID)
            Prefs.cameraOn = true
        }
        home.reloadDevices()
        NotificationCenter.default.post(name: .prefsChanged, object: nil)
        refreshTick()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
