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

# Finder integration (spruce:// links, Dock drops / Open With, and the Services menu)
# is declared in Support/Info.plist; make sure the result is still a valid plist.
PLIST="$APP/Contents/Info.plist"
for key in CFBundleURLTypes CFBundleDocumentTypes NSServices; do
  if ! plutil -extract "$key" xml1 -o /dev/null "$PLIST" >/dev/null 2>&1; then
    echo "error: Support/Info.plist is missing $key" >&2
    exit 1
  fi
done
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
