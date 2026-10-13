#!/usr/bin/env bash
# Builds Spruce.app from the Swift package, without needing the Xcode GUI.
#
#   ./scripts/build-app.sh                 # release build for this Mac's architecture
#   UNIVERSAL=1 ./scripts/build-app.sh     # arm64 + x86_64
#
# Signing is automatic:
#   * If your keychain has a "Developer ID Application" certificate, the app is signed
#     with it (hardened runtime, secure timestamp), then notarized by Apple and stapled
#     when notarization credentials are stored under the keychain profile
#     NOTARY_PROFILE (default "spruce-notary"). One-time setup: README, "Signed builds
#     on your Mac". Privacy grants such as Full Disk Access then survive every rebuild.
#   * Otherwise (e.g. on CI) it is signed ad-hoc; macOS treats every rebuild as a new app.
#
#   SIGN_IDENTITY="<name or SHA-1>"  use a specific certificate ("-" forces ad-hoc)
#   NOTARIZE=0                       sign with Developer ID but skip notarization
#
# Output: build/Spruce.app and build/Spruce.zip
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Spruce"
BUNDLE_ID="${BUNDLE_ID:-com.mitmi.spruce}"
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
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

# --- Signing ---------------------------------------------------------------------------
# With no SIGN_IDENTITY set, use the first "Developer ID Application" certificate in the
# keychain (by its SHA-1, so several teams can't make the choice ambiguous). Without one
# — e.g. on CI — fall back to an ad-hoc signature.
# (Read once into a variable: piping into `grep -q` under pipefail can misreport a match.)
IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
if [[ -z "$SIGN_IDENTITY" ]]; then
  DEVID_LINE="$(grep -m1 '"Developer ID Application:' <<<"$IDENTITIES" || true)"
  if [[ -n "$DEVID_LINE" ]]; then
    SIGN_IDENTITY="$(awk '{print $2}' <<<"$DEVID_LINE")"
    SIGN_NAME="$(sed -E 's/^[^"]*"(.*)"$/\1/' <<<"$DEVID_LINE")"
  else
    SIGN_IDENTITY="-"
  fi
fi
SIGN_NAME="${SIGN_NAME:-$SIGN_IDENTITY}"

# Is the chosen identity (given as a SHA-1 or a name) a Developer ID certificate?
IS_DEVELOPER_ID=0
if [[ "$SIGN_IDENTITY" != "-" ]]; then
  IDENTITY_LINES="$(grep -F -- "$SIGN_IDENTITY" <<<"$IDENTITIES" || true)"
  if [[ "$IDENTITY_LINES" == *'"Developer ID Application:'* ]]; then
    IS_DEVELOPER_ID=1
  fi
fi

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  echo "==> Signing ad-hoc (no Developer ID certificate in use)"
  TIMESTAMP_FLAG="--timestamp=none"
elif [[ "$IS_DEVELOPER_ID" == "1" ]]; then
  echo "==> Signing with $SIGN_NAME"
  # Notarization requires the hardened runtime and a secure timestamp from Apple.
  TIMESTAMP_FLAG="--timestamp"
else
  echo "==> Signing with $SIGN_NAME (not a Developer ID certificate; it won't be notarized)"
  TIMESTAMP_FLAG="--timestamp=none"
fi

codesign --force --options runtime "$TIMESTAMP_FLAG" \
  --entitlements Support/Spruce.entitlements \
  --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

# --- Notarization (Developer ID only) ---------------------------------------------------
# One-time setup: store credentials in the keychain under NOTARY_PROFILE (see README,
# "Signed builds on your Mac"). NOTARIZE=0 skips this step.
NOTARY_PROFILE="${NOTARY_PROFILE:-spruce-notary}"
NOTARIZED=0
if [[ "$IS_DEVELOPER_ID" == "1" && "${NOTARIZE:-1}" != "0" ]]; then
  if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "warning: no notarization credentials named \"$NOTARY_PROFILE\" in your keychain — skipping notarization." >&2
    echo "         Store them once with: xcrun notarytool store-credentials $NOTARY_PROFILE ...  (see README)" >&2
  else
    echo "==> Notarizing with Apple (this usually takes a minute or two)"
    SUBMIT_ZIP="$OUT/$APP_NAME-notarize.zip"
    rm -f "$SUBMIT_ZIP"
    ditto -c -k --keepParent "$APP" "$SUBMIT_ZIP"
    SUBMIT_LOG="$OUT/notarize.log"
    if ! xcrun notarytool submit "$SUBMIT_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1 | tee "$SUBMIT_LOG"; then
      echo "error: notarization submission failed (see $SUBMIT_LOG)" >&2
      exit 1
    fi
    rm -f "$SUBMIT_ZIP"
    if ! grep -q "status: Accepted" "$SUBMIT_LOG"; then
      SUBMISSION_ID="$(grep -m1 -E '^[[:space:]]*id:' "$SUBMIT_LOG" | awk '{print $2}')"
      echo "error: Apple did not accept the app. Details: xcrun notarytool log ${SUBMISSION_ID:-<id>} --keychain-profile $NOTARY_PROFILE" >&2
      exit 1
    fi
    echo "==> Stapling the notarization ticket"
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
    NOTARIZED=1
  fi
fi

if [[ "$NOTARIZED" == "1" ]]; then
  echo "==> Gatekeeper check"
  spctl --assess --type execute --verbose=2 "$APP"
fi

echo "==> Zipping"
rm -f "$OUT/$APP_NAME.zip"
ditto -c -k --keepParent "$APP" "$OUT/$APP_NAME.zip"
if [[ "$NOTARIZED" == "1" ]]; then
  echo "==> Done: $APP (signed by $SIGN_NAME, notarized and stapled)"
elif [[ "$SIGN_IDENTITY" == "-" ]]; then
  echo "==> Done: $APP (ad-hoc signed)"
else
  echo "==> Done: $APP (signed by $SIGN_NAME, not notarized)"
fi
