#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${CONFIGURATION:-debug}"
swift build -c "$configuration"
bin_dir="$(swift build -c "$configuration" --show-bin-path)"
app="$PWD/dist/Sony Companion.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/SonyCompanion" "$app/Contents/MacOS/SonyCompanion"
cp Resources/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
printf 'Built %s\n' "$app"
if [[ "${1:-}" == "--run" ]]; then
    open "$app"
elif [[ "${1:-}" == "--demo" ]]; then
    open "$app" --args --demo
fi
