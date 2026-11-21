#!/bin/sh
set -eu
fork_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
fork_build="$fork_root/build/fork-benchmark"
mkdir -p "$fork_build/modules"
cp "$fork_root/tools/fork/ReceiverBenchmark.swift" "$fork_build/main.swift"
swiftc -O -module-cache-path "$fork_build/modules" \
    "$fork_root/Shared/AnnexBLayout.swift" \
    "$fork_root/Shared/AVCCBlockBuffer.swift" \
    "$fork_build/main.swift" -o "$fork_build/receiver-benchmark"
"$fork_build/receiver-benchmark"
