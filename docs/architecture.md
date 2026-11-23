# Architecture

Orbcast is a single-target AppKit app written in Swift, with no third-party dependencies and no Xcode project. It's compiled with `swiftc` by [`scripts/build.sh`](../scripts/build.sh).

## Source map

| File | Responsibility |
| --- | --- |
| [`main.swift`](../Sources/main.swift) | `AppDelegate`: app lifecycle, menus, menu bar item, global hotkeys, the record / stop / pause / restart flow |
| [`Recorder.swift`](../Sources/Recorder.swift) | Screen + audio capture with ScreenCaptureKit, encoding with AVAssetWriter, pause / resume |
| [`CameraBubble.swift`](../Sources/CameraBubble.swift) | The floating camera window (AVCaptureSession + preview layer), shapes and sizes |
| [`HomeWindow.swift`](../Sources/HomeWindow.swift) | The control panel UI and device pickers |
| [`Overlays.swift`](../Sources/Overlays.swift) | Recording bar, mic level meter, countdown, click-highlight overlay |
| [`ReviewWindow.swift`](../Sources/ReviewWindow.swift) | Post-recording player, trim, MP4 export, copy, delete |
| [`PermissionsWindow.swift`](../Sources/PermissionsWindow.swift) | First-run onboarding for camera, microphone and screen recording |
| [`Prefs.swift`](../Sources/Prefs.swift) | Settings stored in `UserDefaults` |
| [`UI.swift`](../Sources/UI.swift) | Brand colors, buttons, layout helpers |

## How a recording works

```
⌥⌘R ─► countdown ─► Recorder.start()
                        │
          ScreenCaptureKit SCStream ──► screen frames ─┐
                        ├──────────────► mic samples ──┼─► AVAssetWriter ─► .mov
                        └──────────────► app audio ────┘   (H.264/HEVC + AAC)
```

1. **Capture.** `SCStream` captures the chosen display. The microphone is captured by ScreenCaptureKit too (`captureMicrophone`, macOS 15), so screen and voice share one clock.
2. **What's in the video.** The content filter excludes the whole Orbcast app *except* two windows: the camera bubble and the click-highlight overlay. The control panel, recording bar and countdown are never captured. The overlay is a full-screen, click-through window that draws ripples on mouse clicks.
3. **Encoding.** Frames go to an `AVAssetWriter`: H.264 for 1080p, HEVC for 4K, with bitrate scaled to resolution and frame rate. Microphone (mono AAC) and system audio (stereo AAC) are separate tracks. Only complete frames are written, and the session starts on the first one.
4. **Pause / resume.** While paused, samples are dropped. On resume, the paused duration is added to a running offset, and every later sample is re-timed by subtracting it, so the file has no gap or frozen frame.
5. **Stop.** The writer session ends at the current time, not the last frame, so a static screen at the end keeps its full duration. Then the file is finalized.

## Windows

| Window | Type | Level | In the video? |
| --- | --- | --- | --- |
| Control panel | `NSPanel`, HUD style | floating | No |
| Camera bubble | borderless `NSPanel` | status bar | **Yes** |
| Recording bar | borderless `NSPanel` | status bar | No |
| Countdown | borderless `NSPanel` | screen saver | No (gone before capture) |
| Click overlay | borderless, click-through | screen saver | **Yes** |
| Review / Permissions | `NSWindow` | normal / floating | No |

## Global shortcuts

Shortcuts use the Carbon `RegisterEventHotKey` API, which needs no Accessibility permission (unlike an `NSEvent` global key monitor).

## Signing and permissions

The app is ad-hoc signed with an explicit designated requirement (`identifier "com.sathya.orbcast"`). macOS ties Screen Recording and Camera permissions to the designated requirement, so rebuilding the app doesn't reset them.
