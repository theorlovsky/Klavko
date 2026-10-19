#!/bin/bash
# Builds build/Klavko.app (universal: Apple Silicon + Intel) and signs it.
# Signing with a stable certificate keeps the Accessibility permission across rebuilds;
# without one the app is signed ad hoc and the permission must be re-granted after each build.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
# Universal needs Xcode's build system; with Command Line Tools only, build for this Mac's architecture.
if [ -x /Library/Developer/SharedFrameworks/XCBuild.framework/Versions/A/Support/xcbuild ] || xcodebuild -version >/dev/null 2>&1; then
    ARCHS=(--arch arm64 --arch x86_64)
else
    ARCHS=(--arch "$(uname -m)")
    echo "No Xcode: building for $(uname -m) only"
fi

swift build -c "$CONFIG" "${ARCHS[@]}"
BIN_DIR="$(swift build -c "$CONFIG" "${ARCHS[@]}" --show-bin-path)"

APP="build/Klavko.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Klavko" "$APP/Contents/MacOS/Klavko"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Resource bundles of dependencies (FluidAudio's), found by Bundle.module in Contents/Resources.
for bundle in "$BIN_DIR"/*.bundle; do
    [ -e "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done

# Fork policy: never sign ad hoc. An ad-hoc build needs a designated requirement of just
# `identifier "app.klavko.Klavko"`, and macOS would then grant the Accessibility permission (every
# keystroke) to ANY program signed ad hoc with that identifier. A real certificate ties the permission
# to your own signing identity. A free "Apple Development" certificate is enough: Xcode → Settings →
# Accounts → add your Apple ID → Manage Certificates → + Apple Development.
IDENTITY="${KLAVKO_SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
    | awk -F'"' '/Developer ID Application|Apple Development/ { print $2; exit }')}"
if [ -z "$IDENTITY" ] || [ "$IDENTITY" = "-" ]; then
    echo "error: no code signing certificate found (Apple Development or Developer ID Application)." >&2
    echo "       Ad-hoc signing is disabled in this fork; see the comment above this check." >&2
    exit 1
fi
codesign --force --options runtime --timestamp=none --entitlements Resources/Klavko.entitlements \
    --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=1 "$APP"
# The designated requirement must name the certificate, not only the bundle identifier.
REQUIREMENT="$(codesign -d -r- "$APP" 2>&1 | sed -n 's/^designated => //p')"
case "$REQUIREMENT" in
    *certificate*) ;;
    *) echo "error: weak designated requirement: $REQUIREMENT" >&2; exit 1 ;;
esac

echo "Built $APP (signed with: $IDENTITY)"
