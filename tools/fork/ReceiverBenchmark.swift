// Built as main.swift by benchmark-receiver.sh. Measures CPU preparation only;
// no network, hardware decoding, presentation or end-to-end FPS is measured.
import Foundation
import CoreMedia

private var checksum = 0

/// Previous receiver algorithm retained only as a benchmark reference.
private func legacyPrepare(_ data: Data) -> CMBlockBuffer? {
    var nalus: [Data] = []
    data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
        let bytes = raw.bindMemory(to: UInt8.self)
        var start: Int?
        var i = 0
        while i + 4 <= bytes.count {
            if bytes[i] == 0, bytes[i + 1] == 0, bytes[i + 2] == 0, bytes[i + 3] == 1 {
                if let s = start, s < i { nalus.append(Data(bytes[s..<i])) }
                start = i + 4
                i += 4
            } else { i += 1 }
        }
        if let s = start, s < bytes.count { nalus.append(Data(bytes[s...])) }
    }
    var avcc = Data(capacity: nalus.reduce(0) { $0 + $1.count + 4 })
    for nalu in nalus {
        var length = UInt32(nalu.count).bigEndian
        avcc.append(Data(bytes: &length, count: 4))
        avcc.append(nalu)
    }
    var block: CMBlockBuffer?
    guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault,
        memoryBlock: nil, blockLength: avcc.count, blockAllocator: kCFAllocatorDefault,
        customBlockSource: nil, offsetToData: 0, dataLength: avcc.count, flags: 0,
        blockBufferOut: &block) == noErr, let block else { return nil }
    let status = avcc.withUnsafeBytes { raw in
        CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block,
            offsetIntoDestination: 0, dataLength: raw.count)
    }
    return status == noErr ? block : nil
}

private func optimizedPrepare(_ data: Data) -> CMBlockBuffer? {
    AVCCBlockBuffer.make(from: data, nalRanges: AnnexBLayout(data).nalRanges)
}

@inline(never)
private func consume(_ block: CMBlockBuffer?) {
    guard let block else { fatalError("benchmark failed to build AVCC") }
    var pointer: UnsafeMutablePointer<CChar>?
    var length = 0
    guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: &length,
        totalLengthOut: nil, dataPointerOut: &pointer) == noErr, let pointer else {
        fatalError("benchmark block not contiguous")
    }
    checksum &+= length &+ Int(pointer[0]) &+ Int(pointer[length - 1])
}

private func fixture(size: Int, denseByte: UInt8?) -> Data {
    var data = Data("{\"cap\":123,\"snd\":124}".utf8)
    var state: UInt64 = 42
    for type: UInt8 in [0x65, 0x41] {
        data.append(contentsOf: [0, 0, 0, 1, type])
        for i in 0..<size / 2 {
            state = state &* 6_364_136_223_846_793_005 &+ 1
            // Nonzero random bytes include 1 candidates at a realistic rate.
            // Dense cases insert repeated zeroes/ones without new start codes.
            data.append(denseByte != nil && i % 4 < 2 ? denseByte! : UInt8((state >> 32) % 255 + 1))
        }
    }
    return data
}

private func measure(_ data: Data, iterations: Int, optimized: Bool) -> Double {
    let begin = DispatchTime.now().uptimeNanoseconds
    for _ in 0..<iterations {
        autoreleasepool { consume(optimized ? optimizedPrepare(data) : legacyPrepare(data)) }
    }
    let elapsed = DispatchTime.now().uptimeNanoseconds - begin
    return Double(elapsed) / Double(iterations) / 1_000
}

print("case,bytes,iterations_per_round,rounds,legacy_us,optimized_us,speedup")
let cases: [(String, Int, UInt8?, Int)] = [
    ("32KiB-video", 32 * 1024, nil, 600),
    ("256KiB-video", 256 * 1024, nil, 150),
    ("1MiB-keyframe", 1024 * 1024, nil, 50),
    ("32KiB-zero-heavy", 32 * 1024, 0, 600),
    ("32KiB-one-heavy", 32 * 1024, 1, 600),
]
for (name, size, dense, iterations) in cases {
    let data = fixture(size: size, denseByte: dense)
    for _ in 0..<10 { consume(legacyPrepare(data)); consume(optimizedPrepare(data)) }
    var legacy: [Double] = []
    var optimized: [Double] = []
    // Alternate order so cache/thermal changes don't always favor one path.
    for round in 0..<7 {
        if round.isMultiple(of: 2) {
            legacy.append(measure(data, iterations: iterations, optimized: false))
            optimized.append(measure(data, iterations: iterations, optimized: true))
        } else {
            optimized.append(measure(data, iterations: iterations, optimized: true))
            legacy.append(measure(data, iterations: iterations, optimized: false))
        }
    }
    let old = legacy.sorted()[3], new = optimized.sorted()[3]
    print(String(format: "%@,%d,%d,7,%.3f,%.3f,%.2f", name, data.count, iterations, old, new, old / new))
}
print("# checksum=\(checksum)")
