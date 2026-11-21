import Foundation
import CoreMedia

enum ReceiverCoreChecks {
    static func run() throws -> Int {
        var count = 0
        func check(_ condition: Bool, _ message: String) throws {
            guard condition else { throw ForkCoreChecks.Failure(description: message) }
            count += 1
        }
        func bytes(_ block: CMBlockBuffer) -> Data {
            var result = Data(count: CMBlockBufferGetDataLength(block))
            _ = result.withUnsafeMutableBytes { raw in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: raw.count,
                                          destination: raw.baseAddress!)
            }
            return result
        }

        let header = Data("{\"cap\":123,\"snd\":124}".utf8)
        let firstNAL = Data([0x65, 9, 0, 0, 3, 1, 8])  // emulation-prevention bytes are payload
        let secondNAL = Data([0x41, 1, 2])
        let startCode = Data([0, 0, 0, 1])
        let wire = header + startCode + firstNAL + startCode + secondNAL
        let layout = AnnexBLayout(wire)
        try check(layout.metadataRange == 0..<header.count, "telemetry range must precede first start code")
        try check(layout.nalRanges == [header.count + 4..<header.count + 4 + firstNAL.count,
                  wire.count - secondNAL.count..<wire.count], "known NAL offsets must be exact")

        guard let block = AVCCBlockBuffer.make(from: wire, nalRanges: layout.nalRanges) else {
            throw ForkCoreChecks.Failure(description: "direct AVCC allocation failed")
        }
        let expected = Data([0, 0, 0, UInt8(firstNAL.count)]) + firstNAL
            + Data([0, 0, 0, UInt8(secondNAL.count)]) + secondNAL
        try check(bytes(block) == expected, "direct AVCC must preserve exact payload bytes and big-endian lengths")

        let sliced = (Data(repeating: 0xAA, count: 37) + wire).dropFirst(37)
        let slicedLayout = AnnexBLayout(sliced)
        try check(slicedLayout.nalRanges == layout.nalRanges, "nonzero Data indices must not alter byte offsets")
        try check(slicedLayout.metadataRange == layout.metadataRange, "sliced telemetry offsets must be relative")
        let slicedBlock = AVCCBlockBuffer.make(from: sliced, nalRanges: slicedLayout.nalRanges)
        try check(slicedBlock.map(bytes) == expected, "sliced Data must write the same AVCC bytes")

        var transient = wire
        let owned = AVCCBlockBuffer.make(from: transient, nalRanges: layout.nalRanges)
        transient.resetBytes(in: transient.startIndex..<transient.endIndex)
        transient.removeAll()
        try check(owned.map(bytes) == expected, "decoder memory must outlive and be independent of source Data")

        for size in 0...7 {
            let zeroes = Data(repeating: 0, count: size)
            try check(AnnexBLayout(zeroes).nalRanges.isEmpty, "short/zero payload must not invent NALs")
        }
        try check(AnnexBLayout(startCode).nalRanges.isEmpty, "start code without a NAL must be empty")
        try check(AnnexBLayout(startCode + startCode + Data([0x65])).nalRanges == [8..<9],
                  "empty NAL between consecutive start codes must be ignored")
        try check(AnnexBLayout(Data([0, 0, 1, 0x65])).nalRanges.isEmpty,
                  "three-byte start codes are outside the wire contract")
        try check(AnnexBLayout(startCode + firstNAL + startCode).nalRanges == [4..<4 + firstNAL.count],
                  "trailing start code must not become an empty picture")
        try check(AnnexBLayout(startCode + Data([0x65, 0, 0, 0])).nalRanges == [4..<8],
                  "trailing zeroes must stay in the NAL")
        for ranges in [[Range<Int>](), [0..<0], [-1..<1], [0..<wire.count + 1]] {
            try check(AVCCBlockBuffer.make(from: wire, nalRanges: ranges) == nil,
                      "invalid/empty AVCC range must be rejected before pointer access")
        }

        // Differential cases include false zero prefixes, dense zero runs,
        // split-looking headers and empty units. The reference is the previous
        // byte-by-byte scanner, independent of the libc search implementation.
        var random: UInt64 = 0xC0FFEE
        for trial in 0..<400 {
            let size = trial * 13 % 2048
            var candidate = Data()
            for index in 0..<size {
                random = random &* 6_364_136_223_846_793_005 &+ 1
                let byte = UInt8(truncatingIfNeeded: random >> 32)
                candidate.append(trial % 3 == 0 ? byte & 3 : byte)
                if index % 131 == trial % 131 { candidate.append(startCode) }
            }
            let fast = AnnexBLayout(candidate)
            let slow = referenceLayout(candidate)
            try check(fast.nalRanges == slow.ranges && fast.metadataRange == slow.metadata,
                      "scanner differs from legacy at generated case \(trial)")
            if !fast.nalRanges.isEmpty {
                guard let generatedBlock = AVCCBlockBuffer.make(from: candidate, nalRanges: fast.nalRanges) else {
                    throw ForkCoreChecks.Failure(description: "generated AVCC failed at case \(trial)")
                }
                var reference = Data()
                for range in slow.ranges {
                    var length = UInt32(range.count).bigEndian
                    withUnsafeBytes(of: &length) { reference.append(contentsOf: $0) }
                    reference.append(candidate.subdata(in: range))
                }
                try check(bytes(generatedBlock) == reference, "AVCC mismatch at generated case \(trial)")
            }
        }
        return count
    }

    private static func referenceLayout(_ data: Data) -> (ranges: [Range<Int>], metadata: Range<Int>?) {
        let bytes = [UInt8](data)
        var first: Int?
        var start: Int?
        var ranges: [Range<Int>] = []
        var i = 0
        while i + 4 <= bytes.count {
            if bytes[i] == 0, bytes[i + 1] == 0, bytes[i + 2] == 0, bytes[i + 3] == 1 {
                if first == nil { first = i }
                if let start, start < i { ranges.append(start..<i) }
                start = i + 4
                i += 4
            } else {
                i += 1
            }
        }
        if let start, start < bytes.count { ranges.append(start..<bytes.count) }
        return (ranges, first.flatMap { $0 > 0 ? 0..<$0 : nil })
    }
}
