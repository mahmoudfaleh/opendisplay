#!/bin/sh
set -eu
case "${1:-}" in
    "") set -- ;;
    --sanitize) set -- -sanitize=address ;;
    *) echo "Usage: $0 [--sanitize]" >&2; exit 2 ;;
esac
fork_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
fork_build="$fork_root/build/fork-core"
mkdir -p "$fork_build/modules"
cat > "$fork_build/main.swift" <<'SWIFT'
import Foundation
do {
    try ForkCoreChecks.run()
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
SWIFT
swiftc -O "$@" -module-cache-path "$fork_build/modules" \
    "$fork_root/Shared/Protocol.swift" \
    "$fork_root/Shared/WirePacketBuilder.swift" \
    "$fork_root/Shared/AnnexBLayout.swift" \
    "$fork_root/Shared/AVCCBlockBuffer.swift" \
    "$fork_root/Mac/PhoneInfo.swift" \
    "$fork_root/Mac/DesktopPolicy.swift" \
    "$fork_root/Mac/VirtualCanvasSizing.swift" \
    "$fork_root/Mac/StreamConfiguration.swift" \
    "$fork_root/Mac/EncodeWorkCounter.swift" \
    "$fork_root/tools/fork/CoreChecks.swift" \
    "$fork_root/tools/fork/ReceiverCoreChecks.swift" \
    "$fork_build/main.swift" -o "$fork_build/core-checks"
"$fork_build/core-checks"
