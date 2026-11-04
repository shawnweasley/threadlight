#!/bin/bash
set -euo pipefail
THREADLIGHT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
THREADLIGHT_APP="$THREADLIGHT_ROOT/build/Threadlight.app"
test -x "$THREADLIGHT_APP/Contents/MacOS/Threadlight"
plutil -lint "$THREADLIGHT_APP/Contents/Info.plist"
codesign --verify --deep --strict "$THREADLIGHT_APP"
"$THREADLIGHT_APP/Contents/MacOS/Threadlight" --check-assets
"$THREADLIGHT_APP/Contents/MacOS/Threadlight" --diagnose
open "$THREADLIGHT_APP"
sleep 1
pgrep -x Threadlight >/dev/null
echo "Threadlight launch check passed."
