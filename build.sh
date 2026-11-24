#!/bin/sh
# Builds a universal (arm64 + x86_64) Dusk.app and Dusk-macOS.zip in ./build
set -e
cd "$(dirname "$0")"
VERSION="${VERSION:-0.2.0}"
ARCHS="--arch arm64 --arch x86_64"
swift build -c release $ARCHS
BIN="$(swift build -c release $ARCHS --show-bin-path)/Dusk"
APP=build/Dusk.app
rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Dusk"
cp Resources/Dusk.icns "$APP/Contents/Resources/Dusk.icns"
cp -R Resources/Fonts "$APP/Contents/Resources/Fonts"
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Dusk</string>
<key>CFBundleDisplayName</key><string>Dusk</string>
<key>CFBundleIconFile</key><string>Dusk</string>
<key>CFBundleIdentifier</key><string>io.github.s-azizkhan.dusk</string>
<key>CFBundleExecutable</key><string>Dusk</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
<key>NSHumanReadableCopyright</key><string>MIT License. Free and open source.</string>
</dict></plist>
PL
# DEVELOPER_ID="Developer ID Application: Name (TEAMID)" signs for release; otherwise ad-hoc.
if [ -n "$DEVELOPER_ID" ]; then
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP"
else
  codesign --force --sign - "$APP"
fi
rm -f build/Dusk-macOS.zip
ditto -c -k --keepParent "$APP" build/Dusk-macOS.zip
# NOTARY_PROFILE=<name from `xcrun notarytool store-credentials`> notarizes and staples.
if [ -n "$NOTARY_PROFILE" ]; then
  xcrun notarytool submit build/Dusk-macOS.zip --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm -f build/Dusk-macOS.zip
  ditto -c -k --keepParent "$APP" build/Dusk-macOS.zip
  spctl -a -vv "$APP"
fi
echo "Built $APP and build/Dusk-macOS.zip ($VERSION)"
