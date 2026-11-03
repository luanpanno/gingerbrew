#!/bin/bash
# Builds Gingerbrew.app (and optionally a .dmg) from the Swift package.
#
#   scripts/build-app.sh                 # release build for this Mac's architecture
#   UNIVERSAL=1 scripts/build-app.sh     # arm64 + x86_64
#   DMG=1 scripts/build-app.sh           # also create dist/Gingerbrew-<version>.dmg
#
# Signing: ad-hoc by default. Set CODESIGN_IDENTITY="Developer ID Application: …"
# to sign for distribution, and NOTARIZE=1 with NOTARY_PROFILE=<keychain profile>
# (created with `xcrun notarytool store-credentials`) to notarize the .dmg.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
APP_NAME="Gingerbrew"
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Support/Info.plist)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

echo "==> Building $APP_NAME $VERSION ($BUILD_NUMBER)"
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  swift build -c release --arch arm64 --build-path .build/arm64
  swift build -c release --arch x86_64 --build-path .build/x86_64
  BINARY="$(mktemp -d)/$APP_NAME"
  lipo -create -output "$BINARY" \
    ".build/arm64/release/$APP_NAME" ".build/x86_64/release/$APP_NAME"
else
  swift build -c release
  BINARY="$(swift build -c release --show-bin-path)/$APP_NAME"
fi

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/$APP_NAME"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Support/askpass.sh "$APP/Contents/Resources/askpass.sh"
chmod +x "$APP/Contents/Resources/askpass.sh"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"

IDENTITY="${CODESIGN_IDENTITY:--}"
echo "==> Signing (${IDENTITY/#-/ad-hoc})"
if [[ "$IDENTITY" == "-" ]]; then
  codesign --force --sign - "$APP"
else
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi
codesign --verify --strict "$APP"

if [[ "${DMG:-0}" == "1" ]]; then
  DMG_PATH="$DIST/$APP_NAME-$VERSION.dmg"
  echo "==> Creating $DMG_PATH"
  STAGING="$(mktemp -d)"
  cp -R "$APP" "$STAGING/"
  ln -s /Applications "$STAGING/Applications"
  rm -f "$DMG_PATH"
  hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH" >/dev/null
  rm -rf "$STAGING"
  if [[ "$IDENTITY" != "-" ]]; then
    codesign --force --timestamp --sign "$IDENTITY" "$DMG_PATH"
  fi
  if [[ "${NOTARIZE:-0}" == "1" ]]; then
    echo "==> Notarizing"
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "${NOTARY_PROFILE:?set NOTARY_PROFILE}" --wait
    xcrun stapler staple "$DMG_PATH"
  fi
  shasum -a 256 "$DMG_PATH"
fi

echo "==> Done: $APP"
