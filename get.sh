#!/bin/bash
# Perch installer.  curl -fsSL https://raw.githubusercontent.com/NitinKumar004/perch/main/get.sh | bash
#
# curl does not quarantine what it fetches, so an unsigned app installed this way
# launches without the Gatekeeper "unidentified developer" block. (A browser
# download would be quarantined and need a right-click → Open.)
set -euo pipefail

REPO="NitinKumar004/perch"
ZIP_URL="https://github.com/${REPO}/releases/latest/download/Perch.zip"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

echo "▸ downloading Perch…"
curl -fsSL "$ZIP_URL" -o "$TMP/Perch.zip"
echo "  sha256 $(shasum -a 256 "$TMP/Perch.zip" | cut -d' ' -f1)"
unzip -q "$TMP/Perch.zip" -d "$TMP"
[ -d "$TMP/Perch.app" ] || { echo "✗ archive didn't contain Perch.app"; exit 1; }

# /Applications isn't writable for every account — fall back to ~/Applications.
DEST=/Applications
[ -w "$DEST" ] || DEST="$HOME/Applications"
mkdir -p "$DEST"

# Stage then swap, so a failed copy never leaves you with a half-installed app.
STAGE="$DEST/.Perch.app.incoming"
rm -rf "$STAGE"
ditto "$TMP/Perch.app" "$STAGE"
pkill -x Perch 2>/dev/null || true
rm -rf "$DEST/Perch.app"
mv "$STAGE" "$DEST/Perch.app"

# Strip the quarantine flag just in case, and launch.
xattr -dr com.apple.quarantine "$DEST/Perch.app" 2>/dev/null || true
open "$DEST/Perch.app" 2>/dev/null || "$DEST/Perch.app/Contents/MacOS/Perch" >/dev/null 2>&1 &

echo "Done 🐦  Installed to $DEST. Look at your notch — click a pill to connect GitHub."
