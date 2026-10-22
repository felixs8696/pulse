#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
bash scripts/build.sh
swift build -c release --product Pulse --arch x86_64 --scratch-path .build/intel --disable-sandbox --cache-path .build/cache
mkdir -p "$PWD/build/export"
EXPORT_ROOT="$(mktemp -d "$PWD/build/export/package.XXXXXX")"
STAGE="$EXPORT_ROOT/Pulse"
mkdir -p "$STAGE/Claude setup"
ditto "build/Pulse.app" "$STAGE/Pulse.app"
lipo -create .build/release/Pulse .build/intel/x86_64-apple-macosx/release/Pulse -output "$STAGE/Pulse.app/Contents/MacOS/Pulse"
codesign --force --deep --sign - "$STAGE/Pulse.app"
codesign --verify --deep --strict "$STAGE/Pulse.app"
"$STAGE/Pulse.app/Contents/MacOS/Pulse" --verify-resources
python3 scripts/setup-cursor.py --package-only
cp build/pulse-router.vsix "$STAGE/"
cp scripts/setup-claude.py scripts/claude-hook.py "$STAGE/Claude setup/"
cp DISTRIBUTION.md "$STAGE/READ ME.md"
ditto -c -k --sequesterRsrc --keepParent "$STAGE" "$PWD/build/Pulse-macOS.zip"
(cd "$PWD/build" && shasum -a 256 Pulse-macOS.zip > Pulse-macOS.zip.sha256)
echo "Exported: $PWD/build/Pulse-macOS.zip"
