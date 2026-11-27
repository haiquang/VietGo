#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

APP_VERSION="${VIETGO_VERSION:-$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")}"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/VietGo.app"
ZIP_NAME="VietGo-v${APP_VERSION}-macos-arm64.zip"
DMG_NAME="VietGo-v${APP_VERSION}-macos-arm64.dmg"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"
DMG_PATH="$DIST_DIR/$DMG_NAME"

VIETGO_VERSION="$APP_VERSION" bash "$ROOT_DIR/scripts/build_app.sh"

if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "Error: App bundle not found at $APP_BUNDLE" >&2
    exit 1
fi

echo "==> Packaging ZIP: $ZIP_PATH..."
rm -f "$ZIP_PATH" "$DMG_PATH" "$DIST_DIR/SHA256SUMS.txt"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo "==> Packaging DMG: $DMG_PATH..."
STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGE_DIR"' EXIT
cp -R "$APP_BUNDLE" "$STAGE_DIR/VietGo.app"
ln -s /Applications "$STAGE_DIR/Applications"
hdiutil create -volname "VietGo ${APP_VERSION}" -srcfolder "$STAGE_DIR" -ov -format UDZO "$DMG_PATH"

echo "==> Generating SHA256SUMS.txt..."
(cd "$DIST_DIR" && shasum -a 256 "$DMG_NAME" "$ZIP_NAME" > SHA256SUMS.txt)

echo "==> Release artifacts ready in $DIST_DIR:"
cat "$DIST_DIR/SHA256SUMS.txt"
