#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
DEVELOPER_DIR_PATH="$(xcode-select -p)"
TEST_FRAMEWORKS="$DEVELOPER_DIR_PATH/Library/Developer/Frameworks"
TEST_LIBRARIES="$DEVELOPER_DIR_PATH/Library/Developer/usr/lib"
swift test --disable-sandbox --cache-path .build/cache --disable-xctest \
  -Xswiftc -F -Xswiftc "$TEST_FRAMEWORKS" \
  -Xlinker -rpath -Xlinker "$TEST_FRAMEWORKS" \
  -Xlinker -rpath -Xlinker "$TEST_LIBRARIES"
python3 scripts/test_hooks.py
node --test scripts/test_cursor.cjs
