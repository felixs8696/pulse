#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
swift build -c release --product Pulse --disable-sandbox --cache-path .build/cache
APP="$PWD/build/Pulse.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Pulse "$APP/Contents/MacOS/.Pulse.new"
mv "$APP/Contents/MacOS/.Pulse.new" "$APP/Contents/MacOS/Pulse"
cp scripts/Info.plist "$APP/Contents/Info.plist"
cp scripts/claude-hook.py scripts/setup-claude.py "$APP/Contents/Resources/"
cp -R .build/release/Pulse_Pulse.bundle "$APP/Contents/Resources/"
swift -module-cache-path "$CLANG_MODULE_CACHE_PATH" scripts/make-icon.swift
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP"
echo "Built: $APP"
if [[ "${1:-}" == "--run" ]]; then
  open "$APP"
fi
