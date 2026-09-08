#!/bin/bash
#
# Builds a Release WiseEdit.app and installs it to ~/Applications.
# Run from anywhere:  ./tools/build-app.sh
#
set -euo pipefail
cd "$(dirname "$0")/.."

echo "▸ Regenerating Xcode project…"
xcodegen generate >/dev/null

echo "▸ Building Release (first run compiles WhisperKit, ~2–3 min)…"
xcodebuild \
  -project WiseEdit.xcodeproj \
  -scheme WiseEdit \
  -configuration Release \
  -destination 'platform=macOS' \
  -clonedSourcePackagesDirPath .spm-cache \
  -derivedDataPath build \
  build | tail -1

APP="build/Build/Products/Release/Crisp.app"
DEST="$HOME/Applications"

mkdir -p "$DEST"
rm -rf "$DEST/WiseEdit.app"   # remove old-named build if present
rm -rf "$DEST/Crisp.app"
cp -R "$APP" "$DEST/Crisp.app"

echo "✓ Installed: $DEST/Crisp.app"
echo "  Open it from Finder ▸ Applications, or drag it to /Applications."
