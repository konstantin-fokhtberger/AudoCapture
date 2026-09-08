#!/usr/bin/env bash
set -euo pipefail

CONFIGURATION="${1:-debug}"
case "$CONFIGURATION" in
    debug|release) ;;
    *) echo "Usage: $0 [debug|release]" >&2; exit 2 ;;
esac
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
cd "$ROOT_DIR"
BUILD_ARGS=(-c "$CONFIGURATION" --arch arm64)
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
swift build "${BUILD_ARGS[@]}" --product AudoCaptureApp
EXECUTABLE_PATH="$BIN_DIR/AudoCaptureApp"
APP_PARENT="$ROOT_DIR/.build/bundles/$CONFIGURATION"
APP_PATH="$APP_PARENT/AudoCaptureApp.app"
mkdir -p "$APP_PARENT"
STAGING_ROOT="$(mktemp -d "$APP_PARENT/.staging.XXXXXX")"
trap 'rm -rf "$STAGING_ROOT"' EXIT
STAGED_APP="$STAGING_ROOT/AudoCaptureApp.app"
mkdir -p "$STAGED_APP/Contents/MacOS"
cp "$EXECUTABLE_PATH" "$STAGED_APP/Contents/MacOS/AudoCaptureApp"
cp "$ROOT_DIR/Config/Info.plist" "$STAGED_APP/Contents/Info.plist"
mkdir -p "$STAGED_APP/Contents/Resources"
cp "$ROOT_DIR/Config/AppIcon.icns" "$STAGED_APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$STAGED_APP/Contents/PkgInfo"
plutil -lint "$STAGED_APP/Contents/Info.plist"
ARCHS="$(lipo -archs "$STAGED_APP/Contents/MacOS/AudoCaptureApp")"
[[ "$ARCHS" == arm64 ]] || { echo "Expected arm64, found: $ARCHS" >&2; exit 1; }
MINIMUM_OS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$STAGED_APP/Contents/Info.plist")"
BINARY_OS="$(xcrun vtool -show-build "$STAGED_APP/Contents/MacOS/AudoCaptureApp" | awk '$1 == "minos" { print $2 }')"
[[ "$BINARY_OS" == "$MINIMUM_OS" ]] || { echo "Deployment mismatch: binary=$BINARY_OS plist=$MINIMUM_OS" >&2; exit 1; }
# Prefer a stable local development identity so TCC survives binary changes.
# Explicit override: AUDOCAPTURE_SIGNING_IDENTITY=<identity hash or ->.
SIGNING_IDENTITY="${AUDOCAPTURE_SIGNING_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
    DEVELOPMENT_IDENTITIES="$(security find-identity -v -p codesigning | awk '/"Apple Development:/ { print $2 }')"
    IDENTITY_COUNT="$(printf '%s\n' "$DEVELOPMENT_IDENTITIES" | awk 'NF { n++ } END { print n+0 }')"
    case "$IDENTITY_COUNT" in
        0) SIGNING_IDENTITY="-"; echo "Warning: ad-hoc signing; rebuilding may invalidate privacy permissions." >&2 ;;
        1) SIGNING_IDENTITY="$DEVELOPMENT_IDENTITIES" ;;
        *) echo "Multiple development identities: set AUDOCAPTURE_SIGNING_IDENTITY explicitly." >&2; exit 2 ;;
    esac
fi
# Apple Development is for local testing, not a Developer ID/notarized distribution.
codesign --force --sign "$SIGNING_IDENTITY" "$STAGED_APP"
codesign --verify --strict "$STAGED_APP"
# Publish only after successful staging and validation. Debug/release never replace each other.
rm -rf "$APP_PATH"
mv "$STAGED_APP" "$APP_PATH"
echo "$APP_PATH"
