import Foundation

enum BubbleShape: Int, CaseIterable { case circle = 0, rounded, wide }

/// Persistent user settings (UserDefaults-backed).
enum Prefs {
    private static let d = UserDefaults.standard

    private static func bool(_ k: String, _ def: Bool) -> Bool { d.object(forKey: k) as? Bool ?? def }
    private static func int(_ k: String, _ def: Int) -> Int { d.object(forKey: k) as? Int ?? def }

    static var cameraOn: Bool { get { bool("cameraOn", true) } set { d.set(newValue, forKey: "cameraOn") } }
    static var cameraID: String? { get { d.string(forKey: "cameraID") } set { d.set(newValue, forKey: "cameraID") } }
    static var micOn: Bool { get { bool("micOn", true) } set { d.set(newValue, forKey: "micOn") } }
    static var micID: String? { get { d.string(forKey: "micID") } set { d.set(newValue, forKey: "micID") } }
    static var systemAudio: Bool { get { bool("systemAudio", false) } set { d.set(newValue, forKey: "systemAudio") } }
    /// 0 = 1080p 30fps, 1 = 1080p 60fps, 2 = 4K 60fps (HEVC)
    static var quality: Int { get { int("quality", 1) } set { d.set(newValue, forKey: "quality") } }
    static var countdown: Bool { get { bool("countdown", true) } set { d.set(newValue, forKey: "countdown") } }
    static var showCursorClicks: Bool { get { bool("showClicks", true) } set { d.set(newValue, forKey: "showClicks") } }
    static var bubbleShape: BubbleShape {
        get { BubbleShape(rawValue: int("bubbleShape", 0)) ?? .circle }
        set { d.set(newValue.rawValue, forKey: "bubbleShape") }
    }
    static var bubbleSize: Int { get { int("bubbleSize", 1) } set { d.set(newValue, forKey: "bubbleSize") } }
    static var displayID: UInt32? {
        get { (d.object(forKey: "displayID") as? NSNumber)?.uint32Value }
        set { d.set(newValue.map { NSNumber(value: $0) }, forKey: "displayID") }
    }

    static var recordingsFolder: URL {
        let dir = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Orbcast", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

extension Notification.Name {
    static let prefsChanged = Notification.Name("OrbcastPrefsChanged")
}
