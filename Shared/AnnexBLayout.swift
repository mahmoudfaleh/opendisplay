import Foundation
import Darwin

/// Byte offsets into a received frame, not copies of its NAL payloads. Offsets
/// are relative to withUnsafeBytes, so sliced Data with nonzero indices works.
/// OpenDisplay's wire contract uses four-byte start codes exclusively.
struct AnnexBLayout {
    let metadataRange: Range<Int>?
    let nalRanges: [Range<Int>]

    init(_ data: Data) {
        var firstStartCode: Int?
        var ranges: [Range<Int>] = []
        ranges.reserveCapacity(4)
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress, raw.count >= 4 else { return }
            let bytes = raw.bindMemory(to: UInt8.self)
            var naluStart: Int?
            var i = 0
            var scalar = false
            var hits = 0
            var windowStart = 0
            while i <= raw.count - 4 {
                let at: Int
                if scalar {
                    at = i
                } else {
                    // Find the trailing 1, then check its three preceding zeroes.
                    // This skips long zero runs in compressed dark/static frames.
                    guard let one = memchr(base + i + 3, 1, raw.count - i - 3) else { break }
                    at = base.distance(to: UnsafeRawPointer(one)) - 3
                    hits += 1
                    if hits == 16 {
                        // Dense 1 bytes would make libc calls costlier than a
                        // scalar scan. Fall back before that becomes a hot loop.
                        scalar = at - windowStart < 128
                        windowStart = at
                        hits = 0
                    }
                }
                if bytes[at] == 0, bytes[at + 1] == 0, bytes[at + 2] == 0, bytes[at + 3] == 1 {
                    if firstStartCode == nil { firstStartCode = at }
                    if let start = naluStart, start < at { ranges.append(start..<at) }
                    naluStart = at + 4
                    i = at + 4
                } else {
                    i = at + 1
                }
            }
            if let start = naluStart, start < raw.count { ranges.append(start..<raw.count) }
        }
        metadataRange = firstStartCode.flatMap { $0 > 0 ? 0..<$0 : nil }
        nalRanges = ranges
    }
}
