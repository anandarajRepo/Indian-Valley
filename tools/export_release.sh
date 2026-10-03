#!/usr/bin/env bash
# Build the full (non-demo) release for Windows and Linux.
#
#   tools/export_release.sh            # export into build/release/{windows,linux}
#   tools/export_release.sh --zip      # also zip each platform for upload
#
# Needs Godot 4.2 on PATH (or GODOT=/path/to/godot) with matching export
# templates installed. Unlike the itch.io demo presets, these builds carry no
# "demo" feature tag, so the game carries on past Year 1.
set -euo pipefail

GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VERSION="$(grep -oP 'config/version="\K[^"]+' project.godot)"

echo "== Smoke test"
"$GODOT" --headless res://tests/SmokeTest.tscn

mkdir -p build/release/windows build/release/linux
touch build/.gdignore   # keep Godot from importing the exported files
"$GODOT" --headless --export-release "Windows (release)" build/release/windows/IndianValley.exe
"$GODOT" --headless --export-release "Linux (release)"   build/release/linux/IndianValley.x86_64

if [[ "${1:-}" == "--zip" ]]; then
  for platform in windows linux; do
    (cd build/release/$platform && zip -qr "../IndianValley-$VERSION-$platform.zip" .)
  done
  echo "Zips: build/release/IndianValley-$VERSION-{windows,linux}.zip"
fi
echo "Done — v$VERSION builds are in build/release/"
