#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
xcrun swiftc Sources/Weather.swift Sources/ClockModel.swift Tests/ClockModelTests.swift \
  -module-cache-path build/module-cache -o build/ClockModelTests
build/ClockModelTests
xcrun swiftc Sources/Weather.swift Sources/ClockModel.swift Tests/WeatherTests.swift \
  -module-cache-path build/module-cache -o build/WeatherTests
build/WeatherTests
xcrun swiftc Sources/Weather.swift Sources/WeatherEffects.swift Sources/ClockModel.swift Sources/SenseClockView.swift Tests/WeatherAnimationTests.swift \
  -module-cache-path build/module-cache -framework AppKit -framework ScreenSaver -o build/WeatherAnimationTests
build/WeatherAnimationTests
xcrun clang -fobjc-arc Tests/ScreenSaverSmokeTests.m -framework AppKit -framework ScreenSaver -o build/ScreenSaverSmokeTests
CHECK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/senseclock-check.XXXXXX")"
trap 'rm -rf "$CHECK_DIR"' EXIT
ditto -x -k build/SenseClock.zip "$CHECK_DIR"
codesign --verify --deep --strict "$CHECK_DIR/SenseClock.saver"
codesign --verify --deep --strict "$CHECK_DIR/SenseClock Preview.app"
lipo -info "$CHECK_DIR/SenseClock.saver/Contents/MacOS/SenseClock"
build/ScreenSaverSmokeTests "$CHECK_DIR/SenseClock.saver"
"$CHECK_DIR/SenseClock Preview.app/Contents/MacOS/SenseClockPreview" --snapshot "$PWD/build/preview.png"
