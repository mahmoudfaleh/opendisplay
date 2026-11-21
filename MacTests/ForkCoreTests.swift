import XCTest

final class ForkCoreTests: XCTestCase {
    func testHighRefreshNegotiationAndWireCompatibility() throws {
        try ForkCoreChecks.run()
    }
}
