#!/bin/bash
# Runs the unit tests. With only the Command Line Tools installed (no Xcode),
# SwiftPM can lose the swift-testing macro plugin path on incremental builds,
# so pass it explicitly.
set -euo pipefail
cd "$(dirname "$0")/.."
DEV_DIR="$(xcode-select -p)"
EXTRA=()
PLUGINS="$DEV_DIR/usr/lib/swift/host/plugins/testing"
if [[ "$DEV_DIR" == *CommandLineTools* && -d "$PLUGINS" ]]; then
  EXTRA=(-Xswiftc -plugin-path -Xswiftc "$PLUGINS")
fi
exec swift test "${EXTRA[@]+"${EXTRA[@]}"}" "$@"
