#!/bin/sh
set -eu
fork_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$fork_root"
mkdir -p build/fork-core/modules
# Compile the actual shared receiver at its oldest supported Mac SDK floor.
# This checks the core used by iOS too, but does not replace an iOS app build.
if swiftc -typecheck -swift-version 5 -target arm64-apple-macos12 \
    -module-cache-path build/fork-core/modules \
    -import-objc-header Mac/OpenSidecarMac-Bridging-Header.h \
    Shared/*.swift Mac/Log.swift Mac/LogPolicies.swift \
    > build/fork-core/receiver-typecheck.log 2>&1; then
    echo "PASS: shared receiver typechecked at macOS 12 floor (warnings: build/fork-core/receiver-typecheck.log)"
else
    cat build/fork-core/receiver-typecheck.log
    exit 1
fi
