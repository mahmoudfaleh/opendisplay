import Foundation

/// A snapshot of active fingers in the streamed display's coordinate space.
/// Omitted IDs have lifted. A session token scopes frames to one digitizer.
struct DirectTouchFrame: Decodable {
    static let messageType = "directTouchFrame"
    static let sessionMessage = "directTouchSession"
    static let maxContacts = 10

    struct Contact: Codable, Equatable {
        let id: Int
        let x: Double
        let y: Double

        var fields: [String: Any] { ["id": id, "x": x, "y": y] }
    }

    let session: UUID
    let contacts: [Contact]

    var isValid: Bool {
        contacts.count <= Self.maxContacts &&
            Set(contacts.map(\.id)).count == contacts.count &&
            contacts.allSatisfy {
                (1...Self.maxContacts).contains($0.id) &&
                    (0...1).contains($0.x) && (0...1).contains($0.y)
            }
    }
}
