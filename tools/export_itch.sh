#!/usr/bin/env bash
# Build the itch.io demo (Web, Windows, Linux) and optionally push with butler.
#
#   tools/export_itch.sh                  # export all three into build/itch/
#   ITCH_TARGET=user/indian-valley tools/export_itch.sh --push
#
# Needs Godot 4.2 on PATH (or GODOT=/path/to/godot) with matching export
# templates installed. Every preset carries the "demo" feature tag, so these
# builds end after Year 1 with a thank-you screen.
set -euo pipefail

GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "== Smoke test"
"$GODOT" --headless res://tests/SmokeTest.tscn

mkdir -p build/itch/web build/itch/windows build/itch/linux
touch build/.gdignore   # keep Godot from importing the exported files
"$GODOT" --headless --export-release "Web (itch.io demo)"     build/itch/web/index.html
"$GODOT" --headless --export-release "Windows (itch.io demo)" build/itch/windows/IndianValley.exe
"$GODOT" --headless --export-release "Linux (itch.io demo)"   build/itch/linux/IndianValley.x86_64

if [[ "${1:-}" == "--push" ]]; then
  : "${ITCH_TARGET:?Set ITCH_TARGET=user/game}"
  VERSION="$(grep -oP 'config/version="\K[^"]+' project.godot)"
  butler push build/itch/web     "$ITCH_TARGET:html5"   --userversion "$VERSION"
  butler push build/itch/windows "$ITCH_TARGET:windows" --userversion "$VERSION"
  butler push build/itch/linux   "$ITCH_TARGET:linux"   --userversion "$VERSION"
fi
echo "Done — builds are in build/itch/"
