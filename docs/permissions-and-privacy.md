# Permissions & privacy

Orbcast runs entirely on your Mac. It has no servers, no accounts, no analytics and no telemetry. It never connects to the internet.

## What Orbcast can access

| Permission | Used for | Used when |
| --- | --- | --- |
| Camera | The camera bubble preview | While the bubble is visible |
| Microphone | Your voice-over | Only while recording, if a microphone is selected |
| Screen & System Audio Recording | Capturing the selected display and, optionally, app audio | Only while recording |

The bubble's camera preview runs while the bubble is visible, so the camera light is on. Hide the bubble or choose **No camera** to turn the camera off.

Orbcast also watches for mouse clicks while a recording runs, only to draw click highlights. Turn this off with **Highlight clicks**. It doesn't record keystrokes.

## What Orbcast stores

| Data | Location |
| --- | --- |
| Recordings and exports | `~/Movies/Orbcast/` |
| Settings (devices, bubble shape and size, quality) | `~/Library/Preferences/com.sathya.orbcast.plist` |

Nothing else is written, and nothing leaves your Mac unless you share a file yourself.

## Revoking access

Open **System Settings › Privacy & Security**, choose **Camera**, **Microphone** or **Screen & System Audio Recording**, and turn Orbcast off.

## Verify it yourself

Orbcast is open source. The whole app is about 2,000 lines of Swift in [`Sources/`](../Sources), with no third-party dependencies.
