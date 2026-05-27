import XCTest
@testable import Jerusalem

/// Phase 0 smoke test: proves the test target builds, links against the app
/// module, and can reference its types. Real coverage grows from Phase 1.
final class AppSmokeTests: XCTestCase {
    func testOperatorModeHasShowAndEdit() {
        XCTAssertEqual(OperatorView.Mode.allCases.count, 2)
        XCTAssertEqual(OperatorView.Mode.show.rawValue, "Show")
        XCTAssertEqual(OperatorView.Mode.edit.rawValue, "Edit")
    }
}
