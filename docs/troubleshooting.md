# Troubleshooting

### macOS says "Apple could not verify Orbcast"

Orbcast isn't notarized yet. Open **System Settings › Privacy & Security**, scroll down and click **Open Anyway**. See [Installation](installation.md#first-launch-apple-could-not-verify-orbcast).

### Screen Recording still shows "Relaunch" after I allowed it

1. Quit Orbcast.
2. In **System Settings › Privacy & Security › Screen & System Audio Recording**, remove any old Orbcast entries with **–**, then turn the current one on.
3. Open Orbcast again.

If it still fails, reset the permission and grant it once more:

```sh
tccutil reset ScreenCapture com.sathya.orbcast
```

### "Couldn't start recording"

Usually the Screen Recording permission is missing or stale. Follow the steps above. If you just plugged in or unplugged a display, pick the screen again in the control panel.

### The camera bubble is black or shows a crossed-out camera

- Check **System Settings › Privacy & Security › Camera** has Orbcast turned on.
- Another app may be holding the camera exclusively. Quit it and toggle the camera in Orbcast.
- Choose a different camera in the control panel, then switch back.

### No sound in my recording

- Check a microphone is selected (not **No microphone**). The level meter on the recording bar should move when you speak.
- Check **System Settings › Privacy & Security › Microphone** has Orbcast turned on.
- System audio is off by default. Turn on **System audio** to record app sounds.
- Some players only play the first audio track. Export to MP4 for the widest compatibility.

### The shortcut ⌥⌘R doesn't work

Another app may already use the same shortcut. Quit apps with global shortcuts (window managers, clipboard tools) and try again, or use the **Start Recording** button or the menu bar icon.

### "Nothing was recorded"

The recording stopped before the first frame arrived, usually because it was stopped right away. Record for at least a second.

### The video is choppy or the file is large

Use **1080p · 30 fps** for long recordings or older Macs. 4K at 60 fps produces large files by design.

### Export failed

Make sure there's free disk space and the original `.mov` still exists in `~/Movies/Orbcast`. Then try again from the review window.

### Still stuck?

[Open an issue](https://github.com/heres-sathya/orbcast/issues/new) with your macOS version, Mac model and the steps to reproduce.
