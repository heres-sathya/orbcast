import AppKit
import AVFoundation
import ScreenCaptureKit

struct RecordingOptions {
    var displayID: UInt32
    var micOn: Bool
    var micID: String?
    var systemAudio: Bool
    var quality: Int              // 0 = 1080p30, 1 = 1080p60, 2 = 4K60
    var includedWindowNumbers: [Int]  // our own windows that SHOULD appear (camera bubble, click overlay)
}

/// Screen + mic + system audio recorder built on ScreenCaptureKit and AVAssetWriter.
/// Supports pause/resume (timestamps are shifted so the file has no gaps).
final class Recorder: NSObject, SCStreamOutput, SCStreamDelegate {
    enum State { case idle, recording, paused }
    private(set) var state: State = .idle

    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoIn: AVAssetWriterInput?
    private var micIn: AVAssetWriterInput?
    private var sysIn: AVAssetWriterInput?
    private let q = DispatchQueue(label: "orbcast.writer", qos: .userInteractive)

    // Accessed only on `q`
    private var sessionStarted = false
    private var paused = false
    private var pauseStartedAt = CMTime.invalid
    private var offset = CMTime.zero
    private var lastVideoPTS = CMTime.invalid

    // Main thread
    private var startDate: Date?
    private var pauseDate: Date?
    private var pausedTotal: TimeInterval = 0
    private(set) var fileURL: URL?

    var onUnexpectedStop: ((Error) -> Void)?
    /// Microphone level 0...1, delivered on main thread.
    var onMicLevel: ((Float) -> Void)?

    var elapsed: TimeInterval {
        guard let s = startDate else { return 0 }
        return (pauseDate ?? Date()).timeIntervalSince(s) - pausedTotal
    }

    private static func hostNow() -> CMTime { CMClockGetTime(CMClockGetHostTimeClock()) }
    private func err(_ s: String) -> NSError {
        NSError(domain: "Orbcast", code: 1, userInfo: [NSLocalizedDescriptionKey: s])
    }

    func start(_ o: RecordingOptions, to url: URL) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first(where: { $0.displayID == o.displayID }) ?? content.displays.first else {
            throw err("No display found to record.")
        }

        // Hide all Orbcast windows from the video except the camera bubble / click overlay.
        let pid = ProcessInfo.processInfo.processIdentifier
        let included = content.windows.filter { o.includedWindowNumbers.contains(Int($0.windowID)) }
        let filter: SCContentFilter
        if let me = content.applications.first(where: { $0.processID == pid }) {
            filter = SCContentFilter(display: display, excludingApplications: [me], exceptingWindows: included)
        } else {
            filter = SCContentFilter(display: display, excludingWindows: [])
        }

        // Output size
        let scale = CGFloat(filter.pointPixelScale)
        let native = CGSize(width: filter.contentRect.width * scale, height: filter.contentRect.height * scale)
        let box = o.quality == 2 ? CGSize(width: 3840, height: 2400) : CGSize(width: 1920, height: 1200)
        let f = min(1, min(box.width / native.width, box.height / native.height))
        let w = Int(native.width * f) & ~1
        let h = Int(native.height * f) & ~1
        let fps = o.quality == 0 ? 30 : 60

        let cfg = SCStreamConfiguration()
        cfg.width = w
        cfg.height = h
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        cfg.showsCursor = true
        cfg.queueDepth = 8
        cfg.colorSpaceName = CGColorSpace.sRGB
        cfg.capturesAudio = o.systemAudio
        cfg.excludesCurrentProcessAudio = true
        cfg.sampleRate = 48000
        cfg.channelCount = 2
        if o.micOn {
            cfg.captureMicrophone = true
            if let id = o.micID { cfg.microphoneCaptureDeviceID = id }
        }

        // Writer
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let codec: AVVideoCodecType = o.quality == 2 ? .hevc : .h264
        let bitrate = Double(w * h * fps) * (codec == .hevc ? 0.07 : 0.11)
        var comp: [String: Any] = [
            AVVideoAverageBitRateKey: bitrate,
            AVVideoExpectedSourceFrameRateKey: fps,
            AVVideoMaxKeyFrameIntervalKey: fps * 2,
            AVVideoAllowFrameReorderingKey: false,
        ]
        if codec == .h264 { comp[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel }
        let v = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: codec, AVVideoWidthKey: w, AVVideoHeightKey: h,
            AVVideoCompressionPropertiesKey: comp,
        ])
        v.expectsMediaDataInRealTime = true
        guard writer.canAdd(v) else { throw err("Can't configure video encoder.") }
        writer.add(v)

        func audioInput(channels: Int) -> AVAssetWriterInput {
            let a = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: channels,
                AVEncoderBitRateKey: channels == 1 ? 128_000 : 192_000,
            ])
            a.expectsMediaDataInRealTime = true
            return a
        }
        var mic: AVAssetWriterInput?
        var sys: AVAssetWriterInput?
        if o.micOn { let a = audioInput(channels: 1); if writer.canAdd(a) { writer.add(a); mic = a } }
        if o.systemAudio { let a = audioInput(channels: 2); if writer.canAdd(a) { writer.add(a); sys = a } }
        guard writer.startWriting() else { throw writer.error ?? err("Couldn't start writing the file.") }

        q.sync {
            self.writer = writer
            self.videoIn = v
            self.micIn = mic
            self.sysIn = sys
            self.sessionStarted = false
            self.paused = false
            self.offset = .zero
            self.lastVideoPTS = .invalid
        }

        let s = SCStream(filter: filter, configuration: cfg, delegate: self)
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: q)
        if o.systemAudio { try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: q) }
        if o.micOn { try s.addStreamOutput(self, type: .microphone, sampleHandlerQueue: q) }
        do {
            try await s.startCapture()
        } catch {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        stream = s
        fileURL = url
        startDate = Date()
        pauseDate = nil
        pausedTotal = 0
        state = .recording
    }

    func pause() {
        guard state == .recording else { return }
        q.async { self.paused = true; self.pauseStartedAt = Self.hostNow() }
        pauseDate = Date()
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        q.async {
            if self.pauseStartedAt.isValid {
                self.offset = CMTimeAdd(self.offset, CMTimeSubtract(Self.hostNow(), self.pauseStartedAt))
            }
            self.paused = false
        }
        if let p = pauseDate { pausedTotal += Date().timeIntervalSince(p) }
        pauseDate = nil
        state = .recording
    }

    /// Stops and finalizes the file. Returns its URL, or nil if nothing was recorded.
    func stop() async -> URL? {
        guard state != .idle else { return nil }
        let s = stream
        stream = nil
        state = .idle
        startDate = nil
        try? await s?.stopCapture()
        let url = fileURL
        return await withCheckedContinuation { (cont: CheckedContinuation<URL?, Never>) in
            q.async {
                guard let writer = self.writer, writer.status == .writing, self.sessionStarted else {
                    self.writer?.cancelWriting()
                    if let url { try? FileManager.default.removeItem(at: url) }
                    self.clear()
                    cont.resume(returning: nil)
                    return
                }
                // Session ends "now" (or at the pause point) so a static last frame keeps its duration.
                let endHost = self.paused ? self.pauseStartedAt : Self.hostNow()
                var end = CMTimeSubtract(endHost, self.offset)
                if self.lastVideoPTS.isValid, CMTimeCompare(end, self.lastVideoPTS) < 0 { end = self.lastVideoPTS }
                writer.endSession(atSourceTime: end)
                self.videoIn?.markAsFinished()
                self.micIn?.markAsFinished()
                self.sysIn?.markAsFinished()
                writer.finishWriting {
                    let ok = writer.status == .completed
                    self.q.async { self.clear() }
                    cont.resume(returning: ok ? url : nil)
                }
            }
        }
    }

    /// Stops and throws the recording away.
    func cancel() async {
        guard state != .idle else { return }
        let s = stream
        stream = nil
        state = .idle
        startDate = nil
        try? await s?.stopCapture()
        let url = fileURL
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            q.async {
                self.writer?.cancelWriting()
                if let url { try? FileManager.default.removeItem(at: url) }
                self.clear()
                cont.resume()
            }
        }
    }

    private func clear() {
        writer = nil; videoIn = nil; micIn = nil; sysIn = nil
        sessionStarted = false; paused = false; offset = .zero; lastVideoPTS = .invalid
    }

    // MARK: SCStreamOutput (runs on q)

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sb.isValid, let writer, writer.status == .writing else { return }
        if type == .microphone { reportLevel(sb) }
        if paused { return }

        switch type {
        case .screen:
            guard Self.isCompleteFrame(sb), let out = retime(sb) else { return }
            let pts = CMSampleBufferGetPresentationTimeStamp(out)
            if !sessionStarted {
                writer.startSession(atSourceTime: pts)
                sessionStarted = true
            }
            if let v = videoIn, v.isReadyForMoreMediaData, v.append(out) { lastVideoPTS = pts }
        case .audio:
            guard sessionStarted, let a = sysIn, a.isReadyForMoreMediaData, let out = retime(sb) else { return }
            a.append(out)
        case .microphone:
            guard sessionStarted, let a = micIn, a.isReadyForMoreMediaData, let out = retime(sb) else { return }
            a.append(out)
        @unknown default:
            break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { self.onUnexpectedStop?(error) }
    }

    private static func isCompleteFrame(_ sb: CMSampleBuffer) -> Bool {
        guard let arr = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = arr.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw) else { return false }
        return status == .complete
    }

    private func retime(_ sb: CMSampleBuffer) -> CMSampleBuffer? {
        if CMTimeCompare(offset, .zero) == 0 { return sb }
        var count: CMItemCount = 0
        CMSampleBufferGetSampleTimingInfoArray(sb, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count)
        guard count > 0 else { return sb }
        var infos = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: count)
        CMSampleBufferGetSampleTimingInfoArray(sb, entryCount: count, arrayToFill: &infos, entriesNeededOut: &count)
        for i in 0..<count {
            infos[i].presentationTimeStamp = CMTimeSubtract(infos[i].presentationTimeStamp, offset)
            if infos[i].decodeTimeStamp.isValid {
                infos[i].decodeTimeStamp = CMTimeSubtract(infos[i].decodeTimeStamp, offset)
            }
        }
        var out: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: sb, sampleTimingEntryCount: count,
                                              sampleTimingArray: &infos, sampleBufferOut: &out)
        return out
    }

    private var lastLevelReport = Date.distantPast
    private func reportLevel(_ sb: CMSampleBuffer) {
        guard let onMicLevel, Date().timeIntervalSince(lastLevelReport) > 0.08 else { return }
        lastLevelReport = Date()
        guard let fmt = CMSampleBufferGetFormatDescription(sb),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmt)?.pointee,
              asbd.mFormatID == kAudioFormatLinearPCM, asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0 else { return }
        var abl = AudioBufferList()
        var block: CMBlockBuffer?
        let st = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sb, bufferListSizeNeededOut: nil, bufferListOut: &abl,
            bufferListSize: MemoryLayout<AudioBufferList>.size, blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil, flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &block)
        guard st == noErr, let data = abl.mBuffers.mData else { return }
        let n = Int(abl.mBuffers.mDataByteSize) / MemoryLayout<Float>.size
        guard n > 0 else { return }
        let p = data.bindMemory(to: Float.self, capacity: n)
        var peak: Float = 0
        for i in stride(from: 0, to: n, by: 4) { peak = max(peak, abs(p[i])) }
        // perceptual-ish scaling
        let db = 20 * log10(max(peak, 0.00001))
        let level = max(0, min(1, (db + 50) / 50))
        DispatchQueue.main.async { onMicLevel(level) }
    }
}
