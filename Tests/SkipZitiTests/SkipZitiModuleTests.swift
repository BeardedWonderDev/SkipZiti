import XCTest
@testable import SkipZiti

final class SkipZitiModuleTests: XCTestCase {
    func testSkipModule() {
        // Presence test that satisfies Skip parity expectations.
        XCTAssertNotNil(SkipZiti.bootstrap)
    }
}
