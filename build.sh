#!/usr/bin/env bash
set -euo pipefail

CONFIG="${1:-release}"
APP="dist/Caliper.app"

swift build -c "$CONFIG"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp ".build/$CONFIG/CaliperApp" "$APP/Contents/MacOS/Caliper"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Ad hoc signature. Enough for macOS to grant the bundle a stable identity on this
# machine. It is not a Developer ID, so a downloaded copy would still be blocked by
# Gatekeeper, which is why Caliper is installed from source.
codesign --force --sign - "$APP"

echo "Built $APP"
