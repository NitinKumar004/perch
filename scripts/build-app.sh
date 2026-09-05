#!/usr/bin/env bash
# Build Perch.app — an unsigned (ad-hoc signed) macOS app bundle.
#
# No Apple Developer ID is used. The app is ad-hoc signed (codesign -s -) so it
# has a *stable* code identity for a given binary, which keeps the Keychain from
# re-prompting on every launch. Distribution is via the curl installer (get.sh),
# which does not quarantine the download, so Gatekeeper stays out of the way.
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="${1:-0.1.0}"
APP="Perch.app"
BUILD_DIR=".build/release"

echo "▸ building release binary…"
swift build -c release

echo "▸ assembling ${APP} (v${VERSION})…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BUILD_DIR/Perch" "$APP/Contents/MacOS/Perch"
sed "s/__VERSION__/${VERSION}/g" packaging/Info.plist > "$APP/Contents/Info.plist"

echo "▸ ad-hoc signing (no Developer ID)…"
codesign --force --deep --sign - "$APP"

echo "✓ built $APP"
codesign -dvv "$APP" 2>&1 | grep -E "Identifier|Signature" || true
