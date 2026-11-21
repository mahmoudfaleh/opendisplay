import Foundation

/// Builds [big-endian length][metadata][video] in one growable allocation.
/// The sender appends NAL bytes directly, avoiding a temporary Data per NAL
/// and two subsequent full-frame copies to prepend metadata and length.
struct WirePacketBuilder {
    private var data: Data

    init(prefix: Data = Data(), payloadCapacity: Int = 0) {
        data = Data(capacity: 4 + prefix.count + max(0, payloadCapacity))
        data.append(contentsOf: [0, 0, 0, 0])
        data.append(prefix)
    }

    mutating func append(_ bytes: UnsafePointer<UInt8>, count: Int) {
        data.append(bytes, count: count)
    }

    mutating func append(_ bytes: Data) {
        data.append(bytes)
    }

    mutating func appendStartCode() {
        data.append(contentsOf: [0, 0, 0, 1])
    }

    mutating func finalize() -> Data? {
        guard let length = UInt32(exactly: data.count - 4) else { return nil }
        var header = length.bigEndian
        withUnsafeBytes(of: &header) { data.replaceSubrange(0..<4, with: $0) }
        return data
    }
}
