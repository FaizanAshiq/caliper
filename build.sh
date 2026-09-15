#!/usr/bin/env bash
set -euo pipefail

CONFIG="${1:-release}"
APP="dist/Caliper.app"

swift build -c "$CONFIG"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp ".build/$CONFIG/CaliperApp" "$APP/Contents/MacOS/Caliper"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Sign with the local identity when there is one, because an ad hoc signature is a
# hash of the binary: every rebuild becomes a new app as far as macOS is concerned,
# and Screen Recording has to be granted all over again. Run scripts/signing-identity.sh
# once to create it. Neither is a Developer ID, so a downloaded copy is still blocked
# by Gatekeeper, which is why Caliper is installed from source.
IDENTITY="${CALIPER_SIGN_IDENTITY:-Caliper Local Signing}"

if security find-identity -p codesigning | grep -qF "$IDENTITY"; then
    codesign --force --sign "$IDENTITY" "$APP"
else
    codesign --force --sign - "$APP"
fi

echo "Built $APP"

if [ "${2:-}" = "--install" ]; then
    DEST="${PREFIX:-/Applications}"
    rm -rf "$DEST/Caliper.app"
    cp -R "$APP" "$DEST/Caliper.app"
    echo "Installed to $DEST/Caliper.app"
fi
