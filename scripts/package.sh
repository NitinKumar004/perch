#!/usr/bin/env bash
# Build Perch.app and zip it for release, printing the SHA-256.
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="${1:-0.1.0}"

bash scripts/build-app.sh "$VERSION"

echo "▸ zipping…"
rm -f Perch.zip
# ditto -c -k preserves the bundle and makes a standard macOS zip.
ditto -c -k --keepParent Perch.app Perch.zip

echo "✓ Perch.zip"
echo "  sha256 $(shasum -a 256 Perch.zip | cut -d' ' -f1)"
