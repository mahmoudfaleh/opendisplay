import Foundation

/// A USB HID digitizer with parallel finger collections. The contact IDs and
/// Confidence flag let macOS treat each contact as a finger.
struct TouchscreenReport {
    typealias Contact = DirectTouchFrame.Contact
    static let contactLimit = DirectTouchFrame.maxContacts
    static let axisMax = 32_767.0

    static func descriptor(widthMM: Int, heightMM: Int) -> Data {
        var bytes: [UInt8] = [
            0x05, 0x0D, 0x09, 0x04, 0xA1, 0x01, // Digitizers / Touch Screen / Application
            0x85, 0x01,                         // Input report 1
        ]
        for _ in 0..<contactLimit {
            bytes += [
                0x05, 0x0D, 0x09, 0x22, 0xA1, 0x02, // Finger collection
                0x15, 0x00, 0x25, 0x01,             // Logical range 0–1
                0x75, 0x01, 0x95, 0x03,             // Three one-bit fields
                0x09, 0x42, 0x09, 0x32, 0x09, 0x47, // Tip Switch, In Range, Confidence
                0x81, 0x02,
                0x75, 0x05, 0x95, 0x01, 0x81, 0x03, // Five padding bits
                0x75, 0x08, 0x09, 0x51, 0x25, UInt8(contactLimit), 0x81, 0x02,
                0x75, 0x10, 0x26, 0xFF, 0x7F,       // 16-bit coordinates, 0–32767
                0x35, 0x00, 0x55, 0x0E, 0x65, 0x11, // Physical units of 0.1 mm
            ]
            for (page, usage, mm) in [(1, 0x30, widthMM), (1, 0x31, heightMM),
                                     (13, 0x48, widthMM), (13, 0x49, heightMM)] {
                bytes += [0x05, UInt8(page), 0x09, UInt8(usage), 0x46]
                appendLE(UInt16(min(6_553, max(1, mm)) * 10), to: &bytes)
                bytes += [0x81, 0x02]
            }
            bytes += [0xC0, 0x35, 0, 0x45, 0, 0x55, 0, 0x65, 0]
        }
        bytes += [
            0x05, 0x0D, 0x09, 0x54, 0x25, UInt8(contactLimit), // Contact Count
            0x75, 0x08, 0x95, 0x01, 0x81, 0x02,
            0x85, 0x02, 0x09, 0x55, 0xB1, 0x02, // Contact Count Maximum, feature 2
            0xC0,
        ]
        return Data(bytes)
    }

    private(set) var active: [Contact] = []

    /// Report lifts explicitly before sending the next snapshot. Keeping the
    /// old IDs in the lift report also handles a completely replaced snapshot.
    mutating func update(_ contacts: [Contact]) -> [Data] {
        let nextIDs = Set(contacts.map(\.id))
        let lifted = active.contains { !nextIDs.contains($0.id) }
        var reports: [Data] = []
        if lifted {
            reports.append(Self.input(active, touching: nextIDs))
        }
        reports.append(Self.input(contacts, touching: nextIDs))
        active = contacts
        return reports
    }

    private static func input(_ contacts: [Contact], touching: Set<Int>) -> Data {
        var bytes: [UInt8] = [1]
        for contact in contacts {
            bytes.append(touching.contains(contact.id) ? 0b111 : 0b100)
            bytes.append(UInt8(contact.id))
            appendLE(UInt16((contact.x * axisMax).rounded()), to: &bytes)
            appendLE(UInt16((contact.y * axisMax).rounded()), to: &bytes)
            appendLE(328, to: &bytes)  // Approximate contact width
            appendLE(328, to: &bytes)  // Approximate contact height
        }
        bytes += repeatElement(0, count: (contactLimit - contacts.count) * 10)
        bytes.append(UInt8(contacts.count))
        return Data(bytes)
    }

    private static func appendLE(_ value: UInt16, to bytes: inout [UInt8]) {
        bytes.append(UInt8(truncatingIfNeeded: value))
        bytes.append(UInt8(value >> 8))
    }
}
