import Foundation
import CoreMedia

/// Copies the selected Annex B payloads straight into a single CoreMedia-owned
/// AVCC allocation. The decoder may retain that memory after the receive buffer
/// is compacted or reused; no transient Swift pointer escapes this function.
enum AVCCBlockBuffer {
    static func make(from data: Data, nalRanges: [Range<Int>]) -> CMBlockBuffer? {
        guard !nalRanges.isEmpty else { return nil }
        var length = 0
        for range in nalRanges {
            guard range.lowerBound >= 0, range.upperBound <= data.count,
                  !range.isEmpty, UInt32(exactly: range.count) != nil else { return nil }
            let (next, overflow) = length.addingReportingOverflow(range.count + 4)
            guard !overflow else { return nil }
            length = next
        }

        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: length,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
            offsetToData: 0, dataLength: length, flags: kCMBlockBufferAssureMemoryNowFlag,
            blockBufferOut: &block) == noErr, let block else { return nil }
        var contiguous = 0
        var pointer: UnsafeMutablePointer<CChar>?
        guard CMBlockBufferGetDataPointer(block, atOffset: 0,
            lengthAtOffsetOut: &contiguous, totalLengthOut: nil,
            dataPointerOut: &pointer) == noErr,
              contiguous == length, let pointer else { return nil }

        data.withUnsafeBytes { raw in
            let destination = UnsafeMutableRawPointer(pointer)
            var offset = 0
            for range in nalRanges {
                var naluLength = UInt32(range.count).bigEndian
                withUnsafeBytes(of: &naluLength) { header in
                    destination.advanced(by: offset).copyMemory(from: header.baseAddress!, byteCount: 4)
                }
                destination.advanced(by: offset + 4).copyMemory(
                    from: raw.baseAddress!.advanced(by: range.lowerBound), byteCount: range.count)
                offset += 4 + range.count
            }
        }
        return block
    }
}
