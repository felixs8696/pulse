#!/bin/bash
# Build a docs-only entry point against the real app views, then render sample data.
set -euo pipefail
cd "$(dirname "$0")/../.."
PULSE_ROOT="$PWD"
mkdir -p "$PWD/.build"
PULSE_RENDER_ROOT="$(mktemp -d "$PWD/.build/screenshots.XXXXXX")"
trap 'rm -rf "$PULSE_RENDER_ROOT"' EXIT
cp Package.swift "$PULSE_RENDER_ROOT/"
cp -R Sources "$PULSE_RENDER_ROOT/"
cp -R Tests "$PULSE_RENDER_ROOT/"
cp scripts/screenshots/main.swift "$PULSE_RENDER_ROOT/Sources/Pulse/App.swift"
# Keep the screenshot store independent from the user's app preferences as well.
python3 - "$PULSE_RENDER_ROOT/Sources/Pulse/SessionStore.swift" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1])
source.write_text(source.read_text().replace('UserDefaults.standard',
    'UserDefaults(suiteName: "PulseDocumentationScreenshots")!'))
PY
export CLANG_MODULE_CACHE_PATH="$PULSE_ROOT/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
swift build --package-path "$PULSE_RENDER_ROOT" --scratch-path "$PULSE_ROOT/.build/screenshots-cache" \
  --disable-sandbox --cache-path "$PULSE_ROOT/.build/cache" --product Pulse
"$PULSE_ROOT/.build/screenshots-cache/debug/Pulse" "$PULSE_ROOT/docs/images"
