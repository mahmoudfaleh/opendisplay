#!/bin/sh
set -eu
fork_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$fork_root"
mkdir -p build/fork-core/modules
# Typecheck the actual sender/capture/input/transport implementation using the
# installed macOS SDK. This does not build the Sparkle-dependent UI or iOS app.
if swiftc -typecheck -swift-version 5 -target arm64-apple-macos14 \
    -module-cache-path build/fork-core/modules \
    -import-objc-header Mac/OpenSidecarMac-Bridging-Header.h \
    Mac/MacSender.swift Mac/VirtualDisplay.swift Mac/VirtualCanvasSizing.swift \
    Mac/StreamConfiguration.swift Mac/EncodeWorkCounter.swift Mac/DesktopPolicy.swift Mac/PhoneInfo.swift \
    Mac/Usbmux.swift Mac/USBAccessory.swift Mac/AndroidUSBFunction.swift \
    Mac/AccessoryDeviceWatcher.swift Mac/DisplayArrangement.swift \
    Mac/OriginRestore.swift Mac/InputInjector.swift Mac/CaptureSourceCheck.swift \
    Mac/TestPatternWindow.swift Mac/Log.swift Mac/LogPolicies.swift \
    Shared/Protocol.swift Shared/WirePacketBuilder.swift Shared/DirectCable.swift \
    Shared/AppStore.swift Shared/LogSnapshot.swift \
    > build/fork-core/sender-typecheck.log 2>&1; then
    echo "PASS: sender implementation typechecked (warnings: build/fork-core/sender-typecheck.log)"
else
    cat build/fork-core/sender-typecheck.log
    exit 1
fi
