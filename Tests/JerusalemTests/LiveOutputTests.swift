import XCTest
import SwiftData
@testable import Jerusalem

/// Phase 3 gate (programmatic parts): edit/live separation and output-screen choice.
/// The full-screen behavior and unplug/replug resilience require real hardware.
final class LiveOutputTests: XCTestCase {

    @MainActor
    private func makeItem(_ context: ModelContext, text: String) -> Item {
        let item = Item(kind: .song, title: "Song")
        let slide = Slide(order: 0, sectionLabel: "V1")
        slide.elements = [SlideElement(kind: .text, text: text)]
        item.slides.append(slide)
        context.insert(item)
        return item
    }

    @MainActor
    func testLiveContentIsASnapshotUnaffectedByModelEdits() {
        let container = try! ModelContainer(
            for: Persistence.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let item = makeItem(ModelContext(container), text: "original")

        let live = LiveState()
        live.arm(LiveState.programSlides(for: item))
        live.next()

        // Edit the underlying model *after* going live — the output must not change.
        item.orderedSlides.first?.orderedElements.first?.text = "EDITED"

        guard case .slide(let renderable) = live.content else {
            return XCTFail("expected a live slide")
        }
        XCTAssertEqual(renderable.elements.first?.text, "original")
    }

    @MainActor
    func testClearResetsOutput() {
        let container = try! ModelContainer(
            for: Persistence.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let item = makeItem(ModelContext(container), text: "line")

        let live = LiveState()
        live.arm(LiveState.programSlides(for: item))
        live.next()
        live.clear()
        XCTAssertEqual(live.content, .empty)
        XCTAssertNil(live.liveSlideID)
    }

    func testOutputScreenPrefersNonMainDisplay() {
        XCTAssertEqual(ScreenSelection.outputIndex(screenCount: 1, mainIndex: 0), 0)
        XCTAssertEqual(ScreenSelection.outputIndex(screenCount: 2, mainIndex: 0), 1)
        XCTAssertEqual(ScreenSelection.outputIndex(screenCount: 2, mainIndex: 1), 0)
        XCTAssertEqual(ScreenSelection.outputIndex(screenCount: 3, mainIndex: 1), 0)
    }
}
