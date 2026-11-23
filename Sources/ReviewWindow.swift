import AppKit
import AVKit
import AVFoundation

/// Shown after a recording: preview, trim, export to MP4, copy, reveal, delete.
final class ReviewWindow: NSWindow, NSWindowDelegate {
    private(set) var url: URL
    private let playerView = AVPlayerView()
    private let player: AVPlayer
    private let info = makeLabel("", size: 11.5)
    private let trimLabel = makeLabel("", size: 11.5, color: Brand.pink)
    private let exportButton = PillButton(title: "Export MP4", color: Brand.accent, icon: "square.and.arrow.up", height: 32, fontSize: 13)
    private var exportedURL: URL?
    private var exportSession: AVAssetExportSession?
    private var progressTimer: Timer?
    var onClose: ((ReviewWindow) -> Void)?

    init(url: URL) {
        self.url = url
        player = AVPlayer(url: url)
        super.init(contentRect: NSRect(x: 0, y: 0, width: 860, height: 600),
                   styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        title = url.deletingPathExtension().lastPathComponent
        titlebarAppearsTransparent = true
        appearance = NSAppearance(named: .darkAqua)
        isReleasedWhenClosed = false
        minSize = NSSize(width: 620, height: 420)
        delegate = self
        buildUI()
        center()
        loadInfo()
    }

    private func buildUI() {
        let bg = hudBackground()
        contentView = bg

        playerView.player = player
        playerView.controlsStyle = .floating
        playerView.showsSharingServiceButton = true
        playerView.wantsLayer = true
        playerView.layer?.cornerRadius = 12
        playerView.layer?.masksToBounds = true

        let heading = makeLabel("Your recording is ready", size: 15, weight: .bold, color: .labelColor)
        let infoStack = NSStackView(views: [heading, info, trimLabel])
        infoStack.orientation = .vertical
        infoStack.alignment = .leading
        infoStack.spacing = 2

        func tool(_ title: String, _ sym: String, _ sel: Selector) -> NSButton {
            let b = NSButton(title: title, image: symbol(sym, size: 12) ?? NSImage(), target: self, action: sel)
            b.bezelStyle = .rounded
            b.controlSize = .large
            b.imagePosition = .imageLeading
            return b
        }
        let trim = tool("Trim", "scissors", #selector(trimTapped))
        let copy = tool("Copy", "doc.on.doc", #selector(copyTapped))
        let reveal = tool("Show in Finder", "folder", #selector(revealTapped))
        let del = tool("Delete", "trash", #selector(deleteTapped))
        del.contentTintColor = .systemRed
        exportButton.target = self
        exportButton.action = #selector(exportTapped)
        exportButton.widthAnchor.constraint(equalToConstant: 140).isActive = true

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let bar = NSStackView(views: [infoStack, spacer, trim, copy, reveal, del, exportButton])
        bar.orientation = .horizontal
        bar.alignment = .centerY
        bar.spacing = 8

        let stack = NSStackView(views: [playerView, bar])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 14
        playerView.setContentHuggingPriority(.defaultLow, for: .vertical)
        pin(stack, in: bg, insets: NSEdgeInsets(top: 38, left: 18, bottom: 16, right: 18))
    }

    private func loadInfo() {
        let asset = AVURLAsset(url: url)
        Task { @MainActor in
            let dur = (try? await asset.load(.duration)).map(CMTimeGetSeconds) ?? 0
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            var dims = ""
            if let track = try? await asset.loadTracks(withMediaType: .video).first,
               let ns = try? await track.load(.naturalSize) {
                dims = " · \(Int(ns.width))×\(Int(ns.height))"
            }
            info.stringValue = "\(formatDuration(dur)) · \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))\(dims)"
        }
    }

    private var trimRange: CMTimeRange? {
        guard let item = player.currentItem else { return nil }
        let start = item.reversePlaybackEndTime.isValid ? item.reversePlaybackEndTime : .zero
        let end = item.forwardPlaybackEndTime.isValid ? item.forwardPlaybackEndTime : item.duration
        guard start.isValid, end.isValid, CMTimeCompare(end, start) > 0 else { return nil }
        if CMTimeCompare(start, .zero) == 0 && CMTimeCompare(end, item.duration) == 0 { return nil }
        return CMTimeRange(start: start, end: end)
    }

    @objc private func trimTapped() {
        guard playerView.canBeginTrimming else { return }
        playerView.beginTrimming { [weak self] result in
            guard let self, result == .okButton else { return }
            if let r = self.trimRange {
                self.trimLabel.stringValue = "Trimmed to \(formatDuration(CMTimeGetSeconds(r.start)))–\(formatDuration(CMTimeGetSeconds(r.end))) · export to save"
                self.exportedURL = nil
                self.exportButton.setTitle("Export MP4", fontSize: 13)
            }
        }
    }

    @objc private func exportTapped() {
        if let done = exportedURL { NSWorkspace.shared.activateFileViewerSelecting([done]); return }
        guard exportSession == nil else { return }
        let asset = AVURLAsset(url: url)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1920x1080) else { return }
        var out = url.deletingPathExtension().appendingPathExtension("mp4")
        if trimRange != nil {
            out = url.deletingLastPathComponent()
                .appendingPathComponent(url.deletingPathExtension().lastPathComponent + " (trimmed).mp4")
        }
        try? FileManager.default.removeItem(at: out)
        session.outputURL = out
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        if let r = trimRange { session.timeRange = r }
        exportSession = session
        exportButton.isEnabled = false
        exportButton.setTitle("Exporting 0%", fontSize: 13)
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self, let s = self.exportSession else { return }
            self.exportButton.setTitle("Exporting \(Int(s.progress * 100))%", fontSize: 13)
        }
        session.exportAsynchronously { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.progressTimer?.invalidate()
                self.exportButton.isEnabled = true
                let status = self.exportSession?.status
                let error = self.exportSession?.error
                self.exportSession = nil
                if status == .completed {
                    self.exportedURL = out
                    self.exportButton.setTitle("Show MP4", fontSize: 13)
                    NSWorkspace.shared.activateFileViewerSelecting([out])
                } else {
                    self.exportButton.setTitle("Export MP4", fontSize: 13)
                    showAlert("Export failed", error?.localizedDescription ?? "Unknown error")
                }
            }
        }
    }

    @objc private func copyTapped() {
        let file = exportedURL ?? url
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([file as NSURL])
        trimLabel.stringValue = "Copied \(file.pathExtension.uppercased()) — paste into Slack, Mail, Finder…"
    }

    @objc private func revealTapped() { NSWorkspace.shared.activateFileViewerSelecting([exportedURL ?? url]) }

    @objc private func deleteTapped() {
        let a = NSAlert()
        a.messageText = "Move this recording to the Trash?"
        a.informativeText = url.lastPathComponent
        a.addButton(withTitle: "Move to Trash")
        a.addButton(withTitle: "Cancel")
        a.beginSheetModal(for: self) { [weak self] r in
            guard let self, r == .alertFirstButtonReturn else { return }
            self.player.pause()
            try? FileManager.default.trashItem(at: self.url, resultingItemURL: nil)
            self.close()
        }
    }

    func windowWillClose(_ notification: Notification) {
        player.pause()
        progressTimer?.invalidate()
        onClose?(self)
    }
}
