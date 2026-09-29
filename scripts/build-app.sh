#!/usr/bin/env bash
# Builds Terminalus.app into ./build.
#   scripts/build-app.sh            release build
#   scripts/build-app.sh --debug    debug build
#   scripts/build-app.sh --open     build, then launch
#   scripts/build-app.sh --install  build, then copy to /Applications
# Signing: ad-hoc by default. Set SIGN_IDENTITY="Your Identity" to sign with a stable certificate so
# macOS privacy permissions (Desktop/Documents/Downloads access) survive rebuilds.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG=release
OPEN=0
INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --debug) CONFIG=debug ;;
    --open) OPEN=1 ;;
    --install) INSTALL=1 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

# The macOS 27 SDK in the Command Line Tools turns SwiftUI's @State into a macro whose plugin only
# ships with Xcode, so build against the macOS 26 SDK when it is available.
if [[ -z "${SDKROOT:-}" ]]; then
  for sdk in /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk; do
    if [[ -d "$sdk" ]]; then export SDKROOT="$sdk"; break; fi
  done
fi
[[ -n "${SDKROOT:-}" ]] && echo "SDK: $SDKROOT"

[[ -f Vendor/SwiftTerm/Package.swift ]] || scripts/bootstrap-swiftterm.sh

echo "Building ($CONFIG)..."
swift build -c "$CONFIG" --product Terminalus
BIN="$(swift build -c "$CONFIG" --show-bin-path)"

BUILD_DIR="${BUILD_DIR:-$ROOT/build}"
APP="$BUILD_DIR/Terminalus.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Terminalus" "$APP/Contents/MacOS/Terminalus"
# SwiftTerm's resource bundle (Metal shader source used by the optional Metal renderer).
for bundle in "$BIN"/*.bundle; do
  [[ -e "$bundle" ]] && ditto "$bundle" "$APP/Contents/Resources/$(basename "$bundle")"
done
cp Support/Info.plist "$APP/Contents/Info.plist"
VERSION="$(cat VERSION 2>/dev/null || echo 1.0.0)"
BUILD_NUMBER="$(date +%Y%m%d%H%M)"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

mkdir -p "$ROOT/build"
ICNS="$ROOT/build/AppIcon.icns"
if [[ ! -f "$ICNS" || scripts/make-icon.swift -nt "$ICNS" ]]; then
  echo "Rendering icon..."
  rm -rf build/AppIcon.iconset
  swift scripts/make-icon.swift build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o "$ICNS"
fi
cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"

IDENTITY="${SIGN_IDENTITY:--}"
codesign --force --deep --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP (signed with: ${SIGN_IDENTITY:-ad-hoc})"

if [[ $INSTALL == 1 ]]; then
  rm -rf /Applications/Terminalus.app
  ditto "$APP" /Applications/Terminalus.app
  echo "Installed /Applications/Terminalus.app"
  APP=/Applications/Terminalus.app
fi
if [[ $OPEN == 1 ]]; then
  open "$APP"
fi
