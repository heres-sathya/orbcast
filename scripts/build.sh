#!/bin/bash
# Builds build/Orbcast.app as a universal (Apple Silicon + Intel) binary.
# Requires macOS 15+ and Xcode Command Line Tools: xcode-select --install
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Orbcast.app"
TMP="build/tmp"
rm -rf "$APP" "$TMP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$TMP/AppIcon.iconset"

echo "→ Icon"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/AppIcon.png --out "$TMP/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d Resources/AppIcon.png --out "$TMP/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$TMP/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

echo "→ Compile (arm64 + x86_64)"
swiftc -O -target arm64-apple-macos15.0  Sources/*.swift -o "$TMP/Orbcast-arm64"
swiftc -O -target x86_64-apple-macos15.0 Sources/*.swift -o "$TMP/Orbcast-x86_64"
lipo -create "$TMP/Orbcast-arm64" "$TMP/Orbcast-x86_64" -output "$APP/Contents/MacOS/Orbcast"

echo "→ Bundle + sign"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Ad-hoc signature with a stable designated requirement, so macOS keeps
# Screen Recording / Camera permissions across rebuilds.
codesign --force --sign - -r='designated => identifier "com.sathya.orbcast"' "$APP"

echo "✓ Built $(pwd)/$APP"
