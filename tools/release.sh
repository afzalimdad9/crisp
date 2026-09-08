#!/bin/bash
#
# Builds, signs (Developer ID + hardened runtime + Sign in with Apple),
# notarizes and staples a distributable Crisp.dmg — the version you can put on a
# website for anyone to download and open with no Gatekeeper warning.
#
# Signs manually with the Developer ID certificate, embedding a Developer ID
# provisioning profile and the Sign in with Apple entitlement. (Xcode can't
# auto-create Developer ID profiles, so we use a manually-created one — the
# capability itself is validated server-side via the App ID.)
#
# Prerequisites (one-time):
#   1. "Developer ID Application" certificate in your login keychain.
#   2. A Developer ID provisioning profile for com.wisedt.WiseEdit, installed in
#      ~/Library/MobileDevice/Provisioning Profiles/ (or pass PROFILE=/path).
#   3. Notarization creds under keychain profile "crisp-notary" (notarytool
#      store-credentials).
#
# Usage:  ./tools/release.sh           (or PROFILE=/path/to.provisionprofile ...)
#
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Crisp"
NOTARY_PROFILE="${NOTARY_PROFILE:-crisp-notary}"
BUILD_APP="build/Build/Products/Release/${APP_NAME}.app"
DIST_DIR="dist"
DMG_PATH="${DIST_DIR}/${APP_NAME}.dmg"
ENTITLEMENTS="WiseEdit/WiseEdit.entitlements"
APP_IDENTIFIER="99V2WR47H6.com.wisedt.WiseEdit"

# Finds an installed Developer ID provisioning profile for our app (distribution
# profiles have no ProvisionedDevices; development ones do).
find_profile() {
  local dir f plist
  for dir in "$HOME/Library/MobileDevice/Provisioning Profiles" \
             "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"; do
    [[ -d "$dir" ]] || continue
    for f in "$dir"/*.provisionprofile "$dir"/*.mobileprovision; do
      [[ -e "$f" ]] || continue
      plist=$(security cms -D -i "$f" 2>/dev/null) || continue
      printf '%s' "$plist" | grep -q "$APP_IDENTIFIER" || continue
      printf '%s' "$plist" | grep -q "ProvisionedDevices" && continue
      echo "$f"; return 0
    done
  done
  return 1
}

# ── Preflight ─────────────────────────────────────────────────────────────────
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
  | awk -F'"' '/Developer ID Application/ {print $2; exit}')
if [[ -z "${IDENTITY:-}" ]]; then
  echo "✗ No \"Developer ID Application\" certificate found in your keychain."
  echo "  Create it in Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates ▸ + ."
  exit 1
fi
echo "▸ Signing identity: $IDENTITY"

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "✗ No notarization creds for keychain profile \"$NOTARY_PROFILE\" (notarytool store-credentials)."
  exit 1
fi

# Sign in with Apple needs a Developer ID profile that GRANTS applesignin. Apple's
# Developer ID profiles currently omit it, so we only embed it when a valid profile
# is found; otherwise we sign a plain (launchable) build with cloud sign-in disabled.
PROFILE="${PROFILE:-$(find_profile || true)}"
USE_APPLESIGNIN=0
if [[ -n "${PROFILE:-}" && -e "${PROFILE:-}" ]] \
   && security cms -D -i "$PROFILE" 2>/dev/null | grep -q "com.apple.developer.applesignin"; then
  USE_APPLESIGNIN=1
  echo "▸ Provisioning profile (with Sign in with Apple): $PROFILE"
else
  echo "▸ No applesignin-capable profile — building plain Developer ID app (cloud sign-in disabled)."
fi

# ── Build ─────────────────────────────────────────────────────────────────────
echo "▸ Regenerating Xcode project…"
xcodegen generate >/dev/null

echo "▸ Building Release…"
# Clear any previously signed/stapled app (a locked bundle breaks resource copy)
# and stale archive/export artifacts.
rm -rf "$BUILD_APP" build/Crisp.xcarchive build/export
xcodebuild \
  -project WiseEdit.xcodeproj \
  -scheme WiseEdit \
  -configuration Release \
  -destination 'platform=macOS' \
  -clonedSourcePackagesDirPath .spm-cache \
  -derivedDataPath build \
  build 2>&1 | grep -E "error:|warning: .*(sign|profile|entitlement)|BUILD SUCCEEDED|BUILD FAILED" || true

[[ -d "$BUILD_APP" ]] || { echo "✗ Build product not found: $BUILD_APP"; exit 1; }

# ── Sign (inside-out, hardened runtime, secure timestamp) ─────────────────────
echo "▸ Signing nested code…"
if [[ -d "$BUILD_APP/Contents/Frameworks" ]]; then
  find "$BUILD_APP/Contents/Frameworks" \
    \( -name "*.framework" -o -name "*.dylib" -o -name "*.bundle" \) -print0 \
    | while IFS= read -r -d '' item; do
        codesign --force --options runtime --timestamp --sign "$IDENTITY" "$item"
      done
fi

if [[ "$USE_APPLESIGNIN" == "1" ]]; then
  echo "▸ Embedding provisioning profile + signing with Sign in with Apple…"
  cp "$PROFILE" "$BUILD_APP/Contents/embedded.provisionprofile"
  codesign --force --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$BUILD_APP"
else
  echo "▸ Signing app (plain Developer ID)…"
  rm -f "$BUILD_APP/Contents/embedded.provisionprofile"
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$BUILD_APP"
fi
codesign --verify --strict --verbose=2 "$BUILD_APP"

# ── Notarize the app, then staple its own ticket ──────────────────────────────
mkdir -p "$DIST_DIR"
ZIP="${DIST_DIR}/${APP_NAME}.zip"
echo "▸ Submitting app to Apple notary (a few minutes)…"
ditto -c -k --keepParent "$BUILD_APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
rm -f "$ZIP"
echo "▸ Stapling ticket into the app…"
xcrun stapler staple "$BUILD_APP"

# ── Package a .dmg, sign + notarize + staple it too ───────────────────────────
echo "▸ Building DMG…"
STAGING=$(mktemp -d)
cp -R "$BUILD_APP" "$STAGING/${APP_NAME}.app"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH" >/dev/null
rm -rf "$STAGING"

echo "▸ Signing + notarizing DMG…"
codesign --force --timestamp --sign "$IDENTITY" "$DMG_PATH"
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG_PATH"

echo
echo "✓ Done. Distributable, notarized disk image:"
echo "    $DMG_PATH"
