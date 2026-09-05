#!/usr/bin/env bash
# Build and launch Perch (background agent — look at your notch).
set -euo pipefail
cd "$(dirname "$0")/.."
swift build
exec swift run Perch
