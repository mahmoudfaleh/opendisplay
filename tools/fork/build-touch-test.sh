#!/bin/sh
set -eu
fork_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
app="$fork_root/build/OpenDisplay Direct Touch Test.app"
contents="$app/Contents"
mkdir -p "$contents/MacOS" "$fork_root/build/fork-core/modules"
swiftc -parse-as-library -swift-version 5 \
    -module-cache-path "$fork_root/build/fork-core/modules" \
    "$fork_root/tools/fork/NativeTouchTest.swift" -o "$contents/MacOS/OpenDisplayDirectTouchTest"
cat > "$contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>OpenDisplayDirectTouchTest</string>
    <key>CFBundleIdentifier</key>
    <string>com.peetzweg.opensidecar.direct-touch-test</string>
    <key>CFBundleName</key>
    <string>OpenDisplay Direct Touch Test</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>NSIsTouchNative</key>
    <true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$app"
printf '%s\n' "$app"
