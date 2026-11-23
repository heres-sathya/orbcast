#!/bin/bash
# Packages build/Orbcast.app into dist/Orbcast.dmg (with an Applications shortcut).
set -euo pipefail
cd "$(dirname "$0")/.."

[ -d build/Orbcast.app ] || { echo "Run scripts/build.sh first"; exit 1; }
rm -rf build/dmg dist && mkdir -p build/dmg dist
cp -R build/Orbcast.app build/dmg/
ln -s /Applications build/dmg/Applications
hdiutil create -volname "Orbcast" -srcfolder build/dmg -ov -format UDZO dist/Orbcast.dmg >/dev/null
echo "✓ Created $(pwd)/dist/Orbcast.dmg"
