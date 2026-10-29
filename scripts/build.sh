#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD="$PWD/build"
mkdir -p "$BUILD/SenseClock.saver/Contents/MacOS" "$BUILD/SenseClock Preview.app/Contents/MacOS" "$BUILD/module-cache"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
COMMON=(Sources/Localization.swift Sources/Weather.swift Sources/WeatherEffects.swift Sources/ClockModel.swift Sources/SenseClockView.swift)
for ARCH in arm64 x86_64; do
  xcrun swiftc "${COMMON[@]}" -sdk "$SDK" -target "$ARCH-apple-macos12.0" \
    -module-cache-path "$BUILD/module-cache" -O -emit-library -module-name SenseClock \
    -framework AppKit -framework ScreenSaver -o "$BUILD/SenseClock-$ARCH"
done
xcrun lipo -create "$BUILD/SenseClock-arm64" "$BUILD/SenseClock-x86_64" -output "$BUILD/SenseClock.saver/Contents/MacOS/SenseClock"
cat > "$BUILD/SenseClock.saver/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>zh-Hans</string><string>zh-Hant</string></array>
<key>CFBundleExecutable</key><string>SenseClock</string>
<key>CFBundleIdentifier</key><string>com.senseclock.screensaver</string>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>CFBundleName</key><string>SenseClock</string>
<key>CFBundlePackageType</key><string>BNDL</string>
<key>CFBundleShortVersionString</key><string>1.6.0</string>
<key>CFBundleVersion</key><string>13</string>
<key>LSMinimumSystemVersion</key><string>12.0</string>
<key>NSPrincipalClass</key><string>SenseClockView</string>
</dict></plist>
PLIST
for ARCH in arm64 x86_64; do
  xcrun swiftc "${COMMON[@]}" Sources/PreviewApp.swift -sdk "$SDK" -target "$ARCH-apple-macos12.0" \
    -module-cache-path "$BUILD/module-cache" -O -framework AppKit -framework ScreenSaver \
    -o "$BUILD/Preview-$ARCH"
done
xcrun lipo -create "$BUILD/Preview-arm64" "$BUILD/Preview-x86_64" -output "$BUILD/SenseClock Preview.app/Contents/MacOS/SenseClockPreview"
cat > "$BUILD/SenseClock Preview.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>zh-Hans</string><string>zh-Hant</string></array>
<key>CFBundleExecutable</key><string>SenseClockPreview</string>
<key>CFBundleIdentifier</key><string>com.senseclock.preview</string>
<key>CFBundleName</key><string>SenseClock Preview</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.6.0</string>
<key>LSMinimumSystemVersion</key><string>12.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
for BUNDLE in "$BUILD/SenseClock.saver" "$BUILD/SenseClock Preview.app"; do
  mkdir -p "$BUNDLE/Contents/Resources/Weather"
  cp -R Assets/Localizations/*.lproj "$BUNDLE/Contents/Resources/"
  for ASSET in cloud-day cloud-storm moon; do
    cp "Assets/Weather/$ASSET.png" "$BUNDLE/Contents/Resources/Weather/"
  done
done
xattr -cr "$BUILD/SenseClock.saver" "$BUILD/SenseClock Preview.app"
codesign --force --sign - "$BUILD/SenseClock.saver"
codesign --force --sign - "$BUILD/SenseClock Preview.app"
# Cloud-managed folders can immediately reattach Finder metadata to bundles.
# Package a clean, verified copy outside that folder without extended attributes.
PACKAGE="$(mktemp -d "${TMPDIR:-/tmp}/senseclock-package.XXXXXX")"
trap 'rm -rf "$PACKAGE"' EXIT
ditto --norsrc --noextattr "$BUILD/SenseClock.saver" "$PACKAGE/SenseClock.saver"
ditto --norsrc --noextattr "$BUILD/SenseClock Preview.app" "$PACKAGE/SenseClock Preview.app"
xattr -cr "$PACKAGE"
codesign --force --sign - "$PACKAGE/SenseClock.saver"
codesign --force --sign - "$PACKAGE/SenseClock Preview.app"
codesign --verify --deep --strict "$PACKAGE/SenseClock.saver"
codesign --verify --deep --strict "$PACKAGE/SenseClock Preview.app"
ditto -c -k --norsrc --noextattr "$PACKAGE" "$BUILD/SenseClock.zip"
echo "Built: $BUILD/SenseClock.saver"
echo "Built: $BUILD/SenseClock Preview.app"
echo "Verified package: $BUILD/SenseClock.zip"
