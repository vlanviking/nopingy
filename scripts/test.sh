#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
swift run --build-system native --disable-sandbox --scratch-path .build --cache-path .build/cache -Xswiftc -module-cache-path -Xswiftc .build/ModuleCache nopingy-checks
