#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCH="$(uname -m)"
case "$ARCH" in arm64|x86_64) ;; *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;; esac
BUILD=(swift build --package-path "$ROOT" --disable-sandbox -c release --arch "$ARCH")
"${BUILD[@]}" --product MacOSToolset
"${BUILD[@]}" --product ClosedLidHelper
BIN="$("${BUILD[@]}" --show-bin-path)"
APP="$ROOT/dist/macOS Toolset.app"
# Recreate only the generated bundle; stale files must not enter a release.
rm -rf "$APP"
mkdir -p "$APP/Contents/Library/HelperTools" "$APP/Contents/Library/LaunchDaemons" "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ROOT/.build/AppIcon.iconset"
cp "$BIN/MacOSToolset" "$APP/Contents/MacOS/MacOSToolset"
cp "$BIN/ClosedLidHelper" "$APP/Contents/Library/HelperTools/ClosedLidHelper"
cp "$ROOT/Resources/local.macostoolset.closedlid.plist" "$APP/Contents/Library/LaunchDaemons/"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE.txt"
cp "$ROOT/scripts/repair-helper.sh" "$APP/Contents/Resources/repair-helper.sh"
swift "$ROOT/scripts/make-icon.swift" "$ROOT/.build/icon-1024.png"
for SIZE in 16 32 128 256 512; do
    sips -z "$SIZE" "$SIZE" "$ROOT/.build/icon-1024.png" --out "$ROOT/.build/AppIcon.iconset/icon_${SIZE}x${SIZE}.png" >/dev/null
    DOUBLE=$((SIZE * 2))
    sips -z "$DOUBLE" "$DOUBLE" "$ROOT/.build/icon-1024.png" --out "$ROOT/.build/AppIcon.iconset/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ROOT/.build/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
SIGNING_IDENTITY="${CODE_SIGN_IDENTITY:--}"
SIGN_ARGS=(--force --sign "$SIGNING_IDENTITY")
if [[ "$SIGNING_IDENTITY" != "-" ]]; then SIGN_ARGS+=(--options runtime --timestamp); fi
codesign "${SIGN_ARGS[@]}" --identifier local.macostoolset.closedlid "$APP/Contents/Library/HelperTools/ClosedLidHelper"
codesign "${SIGN_ARGS[@]}" --identifier local.macostoolset.app "$APP"
codesign --verify --strict "$APP/Contents/Library/HelperTools/ClosedLidHelper"
codesign --verify --strict "$APP"
printf 'Built: %s (%s)\n' "$APP" "$ARCH"
