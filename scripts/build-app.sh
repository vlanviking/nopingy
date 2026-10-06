#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
build_args=(--configuration release --product nopingy --build-system native --disable-sandbox --scratch-path .build --cache-path .build/cache -Xswiftc -module-cache-path -Xswiftc .build/ModuleCache)
if [[ "${1:-}" == "--universal" ]]; then build_args+=(--arch arm64 --arch x86_64); fi
swift build "${build_args[@]}"
binary_directory="$(swift build "${build_args[@]}" --show-bin-path)"
app_directory="$PWD/dist/nopingy.app"
stage_root="$(mktemp -d "$PWD/.build/nopingy-stage.XXXXXX")"
trap 'rm -rf "$stage_root"' EXIT
staged_app="$stage_root/nopingy.app"
mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources" .build/AppIcon.iconset dist
cp "$binary_directory/nopingy" "$staged_app/Contents/MacOS/nopingy"
# Remove debug symbols that can embed the builder's local directory paths.
xcrun strip -S "$staged_app/Contents/MacOS/nopingy"
cp Resources/Info.plist "$staged_app/Contents/Info.plist"
swift -module-cache-path "$CLANG_MODULE_CACHE_PATH" scripts/Icon.swift "$PWD/.build/AppIcon.iconset"
python3 scripts/pack-icon.py .build/AppIcon.iconset "$staged_app/Contents/Resources/AppIcon.icns"
cp LICENSE THIRD_PARTY_NOTICES.md "$staged_app/Contents/Resources/"
codesign --force --deep --sign - "$staged_app"
codesign --verify --deep --strict "$staged_app"
ditto -c -k --keepParent --norsrc --noextattr --noqtn --noacl "$staged_app" "$stage_root/nopingy-mac.zip"
# Keep the previous executable intact if a user is still running that build.
if [[ -d "$app_directory" ]]; then
    previous_root="$(mktemp -d "$PWD/.build/nopingy-previous.XXXXXX")"
    mv "$app_directory" "$previous_root/nopingy.app"
fi
mv "$staged_app" "$app_directory"
mv "$stage_root/nopingy-mac.zip" "$PWD/dist/nopingy-mac.zip"
printf 'Built %s\n' "$app_directory"
