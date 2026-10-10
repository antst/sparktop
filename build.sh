#!/bin/bash
# Build SparkTop.app — native macOS menu bar client for sparkDash.
#
#   ./build.sh                      build dist/SparkTop.app (arm64)
#   UNIVERSAL=1 ./build.sh          build universal (arm64 + x86_64)
#   ./build.sh --install            build and copy to /Applications
#   ./build.sh --open               build, launch with popover open (debug)
#   ./build.sh --open --pin         same, popover stays open (screenshots)
set -euo pipefail
cd "$(dirname "$0")"

CONFIG=release

if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  echo "==> swift build -c $CONFIG (universal: arm64 + x86_64)"
  swift build -c "$CONFIG" --arch arm64 --arch x86_64
else
  echo "==> swift build -c $CONFIG"
  swift build -c "$CONFIG"
fi

# Binary lands in different paths across SwiftPM versions/layouts.
BIN=""
for p in ".build/$CONFIG/SparkTop" ".build/out/Products/$CONFIG/SparkTop" ".build/apple/Products/$CONFIG/SparkTop"; do
  if [[ -f "$p" ]]; then
    BIN="$p"
    break
  fi
done
if [[ -z "$BIN" ]]; then
  echo "error: built binary not found" >&2
  exit 1
fi
echo "==> binary: $BIN ($(lipo -archs "$BIN" 2>/dev/null || echo arm64))"
APP="dist/SparkTop.app"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SparkTop"
cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "==> ad-hoc codesign"
codesign --force --sign - "$APP"

echo "Built: $PWD/$APP"

case "${1:-}" in
  --install)
    echo "==> copying to /Applications"
    rm -rf /Applications/SparkTop.app
    cp -R "$APP" /Applications/SparkTop.app
    echo "Installed: /Applications/SparkTop.app"
    ;;
  --open)
    echo "==> launching with popover open"
    "$APP/Contents/MacOS/SparkTop" --open &
    ;;
esac
