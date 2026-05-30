import XCTest
@testable import Jerusalem

/// Phase 0 smoke test: proves the test target builds, links against the app
/// module, and can reference its types. Real coverage grows from Phase 1.
final class AppSmokeTests: XCTestCase {
    func testSlideEditorModeHasShowAndEdit() {
        XCTAssertEqual(SlideEditorView.EditorMode.allCases.count, 2)
        XCTAssertEqual(SlideEditorView.EditorMode.show.rawValue, "Show")
        XCTAssertEqual(SlideEditorView.EditorMode.edit.rawValue, "Edit")
    }
}
