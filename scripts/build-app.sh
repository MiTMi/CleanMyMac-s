#!/usr/bin/env bash
# Builds Spruce.app from the Swift package, without needing the Xcode GUI.
#
#   ./scripts/build-app.sh                 # release build, ad-hoc signed, native arch
#   UNIVERSAL=1 ./scripts/build-app.sh     # arm64 + x86_64
#   SIGN_IDENTITY="Spruce Local" ./scripts/build-app.sh
#       Sign with a (self-signed) code-signing certificate from your keychain so
#       Full Disk Access and other privacy grants survive rebuilds. With the default
#       ad-hoc signature ("-") macOS treats every rebuild as a new app.
#
# Output: build/Spruce.app and build/Spruce.zip
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Spruce"
BUNDLE_ID="${BUNDLE_ID:-com.mitmi.spruce}"
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
OUT="build"
APP="$OUT/$APP_NAME.app"

ARCH_FLAGS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

echo "==> Building $APP_NAME $VERSION ($BUILD_NUMBER)"
swift build -c release --product "$APP_NAME" "${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}"
BIN_DIR="$(swift build -c release --product "$APP_NAME" "${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}" --show-bin-path)"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

sed -e "s/__BUNDLE_ID__/$BUNDLE_ID/g" \
    -e "s/__VERSION__/$VERSION/g" \
    -e "s/__BUILD__/$BUILD_NUMBER/g" \
    Support/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Finder integration: spruce:// links, files dropped on the Dock icon, and the Services
# menu ("Uninstall with Spruce", "Map Folder with Spruce", "Shred with Spruce" — handled
# by SpruceServices / AppDelegate; they only show the files in a tool, never remove).
# Keys the template already defines are left alone.
PLIST="$APP/Contents/Info.plist"
add_plist_key() {
  if ! plutil -extract "$1" xml1 -o /dev/null "$PLIST" >/dev/null 2>&1; then
    plutil -insert "$1" -json "$2" "$PLIST"
  fi
}
add_plist_key CFBundleURLTypes '[{"CFBundleURLName":"Spruce link","CFBundleURLSchemes":["spruce"]}]'
add_plist_key CFBundleDocumentTypes '[
  {"CFBundleTypeName":"Application","CFBundleTypeRole":"Viewer","LSHandlerRank":"None","LSItemContentTypes":["com.apple.application-bundle"]},
  {"CFBundleTypeName":"Installer Package","CFBundleTypeRole":"Viewer","LSHandlerRank":"None","LSItemContentTypes":["com.apple.installer-package-archive"]},
  {"CFBundleTypeName":"Folder","CFBundleTypeRole":"Viewer","LSHandlerRank":"None","LSItemContentTypes":["public.folder"]},
  {"CFBundleTypeName":"Item","CFBundleTypeRole":"Viewer","LSHandlerRank":"None","LSItemContentTypes":["public.item"]}]'
add_plist_key NSServices '[
  {"NSMenuItem":{"default":"Uninstall with Spruce"},"NSMessage":"uninstallWithSpruce","NSPortName":"Spruce","NSRequiredContext":{},"NSSendFileTypes":["com.apple.application-bundle"]},
  {"NSMenuItem":{"default":"Map Folder with Spruce"},"NSMessage":"mapFolderWithSpruce","NSPortName":"Spruce","NSRequiredContext":{},"NSSendFileTypes":["public.folder"]},
  {"NSMenuItem":{"default":"Shred with Spruce"},"NSMessage":"shredWithSpruce","NSPortName":"Spruce","NSRequiredContext":{},"NSSendFileTypes":["public.item"]}]'
plutil -lint "$PLIST"

# App icon: use Support/AppIcon.icns if present, otherwise render one.
if [[ -f Support/AppIcon.icns ]]; then
  cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
elif [[ -f scripts/make-icon.swift ]] && command -v iconutil >/dev/null; then
  ICONSET="$OUT/AppIcon.iconset"
  rm -rf "$ICONSET" && mkdir -p "$ICONSET"
  if swift scripts/make-icon.swift "$ICONSET" >/dev/null 2>&1; then
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" || true
  fi
fi

echo "==> Signing (identity: $SIGN_IDENTITY)"
codesign --force --options runtime --timestamp=none \
  --entitlements Support/Spruce.entitlements \
  --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "==> Zipping"
rm -f "$OUT/$APP_NAME.zip"
ditto -c -k --keepParent "$APP" "$OUT/$APP_NAME.zip"
echo "==> Done: $APP"
