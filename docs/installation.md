# Installation

## Requirements

- macOS 15 Sequoia or later
- Apple Silicon or Intel Mac (the app is a universal binary)
- A few MB of disk space, plus space for your recordings

## Install

1. Download [**Orbcast.dmg**](https://orbcast.pages.dev/Orbcast.dmg).
2. Open the DMG and drag **Orbcast** onto the **Applications** shortcut.
3. Eject the DMG and open **Orbcast** from Applications or Spotlight.

## First launch: "Apple could not verify Orbcast"

Orbcast is signed but not yet notarized by Apple, so macOS 15 blocks it the first time you open it. This is a one-time step:

1. Click **Done** on the warning.
2. Open **System Settings › Privacy & Security**.
3. Scroll to the **Security** section. Next to *"Orbcast" was blocked*, click **Open Anyway**.
4. Confirm with **Open Anyway** and your password or Touch ID.

On macOS 15, right-clicking the app and choosing Open no longer bypasses this; use the steps above.

If you'd rather not, [build it from source](building-from-source.md). An app you build yourself is never blocked.

## Grant permissions

Orbcast opens a welcome window that walks you through three permissions:

| Permission | Why it's needed | How |
| --- | --- | --- |
| Camera | Shows you in the bubble | Click **Allow** |
| Microphone | Records your voice | Click **Allow** |
| Screen & System Audio Recording | Captures your screen | Click **Allow**, turn on Orbcast in System Settings, then click **Relaunch** |

macOS only applies the Screen Recording permission after the app restarts, which is what **Relaunch** does.

You can reopen this window any time from the shield icon in the control panel or **Orbcast › Permissions…** (<kbd>⌘</kbd><kbd>,</kbd>).

## Update

Download the latest DMG and drag Orbcast into Applications again, replacing the old copy. Your settings and recordings are kept.

## Uninstall

1. Quit Orbcast (<kbd>⌘</kbd><kbd>Q</kbd>).
2. Move **Orbcast** from Applications to the Trash.
3. Optional: delete your settings with `defaults delete com.sathya.orbcast`.
4. Optional: remove its permissions in **System Settings › Privacy & Security** (Camera, Microphone, Screen & System Audio Recording).

Your recordings in `~/Movies/Orbcast` are never deleted automatically.
