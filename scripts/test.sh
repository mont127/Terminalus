#!/usr/bin/env bash
# Runs the TerminalusCore unit tests (swift-testing) with the Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${SDKROOT:-}" && -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then
  export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
fi
[[ -f Vendor/SwiftTerm/Package.swift ]] || scripts/bootstrap-swiftterm.sh
EXTRA=()
# The Command Line Tools keep the swift-testing macro plugin in a subfolder the driver doesn't search.
PLUGINS=/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
[[ -d "$PLUGINS" ]] && EXTRA=(-Xswiftc -plugin-path -Xswiftc "$PLUGINS")
swift test "${EXTRA[@]}" "$@"
