#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/release"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/Porter.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="$DIST_DIR/Porter.iconset"
DMG_STAGING_DIR="$DIST_DIR/dmg"
DMG_BACKGROUND_DIR="$DMG_STAGING_DIR/.background"
DMG_BACKGROUND_PATH="$DMG_BACKGROUND_DIR/background.png"
DMG_TEMP_PATH="$DIST_DIR/Porter-rw.dmg"
DMG_PATH="$DIST_DIR/Porter.dmg"
MOUNT_ROOT=""
VOLUME_PATH=""

cleanup() {
    if [[ -n "$VOLUME_PATH" && -d "$VOLUME_PATH" ]]; then
        hdiutil detach "$VOLUME_PATH" -quiet || true
    fi
    if [[ -n "$MOUNT_ROOT" && -d "$MOUNT_ROOT" ]]; then
        rmdir "$MOUNT_ROOT" || true
    fi
}
trap cleanup EXIT

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT_DIR/.build/module-cache}"

rm -rf "$DIST_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$DMG_STAGING_DIR" "$DMG_BACKGROUND_DIR"

swift build -c release --product Porter --scratch-path "$ROOT_DIR/.build"
swift "$ROOT_DIR/Scripts/render-icon.swift" "$ICONSET_DIR"
swift "$ROOT_DIR/Scripts/render-dmg-background.swift" "$DMG_BACKGROUND_PATH"
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/Porter.icns"

cp "$BUILD_DIR/Porter" "$MACOS_DIR/Porter"
cp "$ROOT_DIR/Packaging/Info.plist" "$CONTENTS_DIR/Info.plist"
chmod +x "$MACOS_DIR/Porter"

if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign - "$APP_DIR"
fi

cp -R "$APP_DIR" "$DMG_STAGING_DIR/Porter.app"
ln -s /Applications "$DMG_STAGING_DIR/Applications"

hdiutil create \
    -volname "Porter" \
    -srcfolder "$DMG_STAGING_DIR" \
    -ov \
    -format UDRW \
    "$DMG_TEMP_PATH"

MOUNT_ROOT="$(mktemp -d "$DIST_DIR/mount.XXXXXX")"
hdiutil attach "$DMG_TEMP_PATH" -readwrite -noverify -noautoopen -mountroot "$MOUNT_ROOT" -quiet
VOLUME_PATH="$MOUNT_ROOT/Porter"

chflags hidden "$VOLUME_PATH/.background"

osascript "$ROOT_DIR/Scripts/setup-dmg-window.applescript" \
    "$VOLUME_PATH" \
    "$VOLUME_PATH/.background/background.png"

hdiutil detach "$VOLUME_PATH" -quiet
VOLUME_PATH=""

hdiutil convert "$DMG_TEMP_PATH" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$DMG_PATH" \
    -quiet

rm -f "$DMG_TEMP_PATH"

echo "$DMG_PATH"
