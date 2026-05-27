import XCTest
import SwiftData
@testable import Jerusalem

/// Phase 4 gate (logic): keyboard-style navigation, panic states, and search —
/// i.e. running a program end to end without the mouse.
final class LiveNavigationTests: XCTestCase {

    /// Builds a real (in-memory) item and returns its program snapshots. The
    /// returned values are independent of the container, which may deallocate.
    @MainActor
    private func makeProgram(slideCount: Int, withText: Bool = true) -> [LiveState.ProgramSlide] {
        let container = try! ModelContainer(
            for: Persistence.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let item = Item(kind: .song, title: "Test")
        for i in 0..<slideCount {
            let slide = Slide(order: i, sectionLabel: "V\(i)")
            if withText { slide.elements = [SlideElement(kind: .text, text: "line \(i)")] }
            item.slides.append(slide)
        }
        context.insert(item)
        try? context.save()
        return LiveState.programSlides(for: item)
    }

    @MainActor
    func testArmDoesNotChangeOutput() {
        let live = LiveState()
        live.arm(makeProgram(slideCount: 3))
        XCTAssertEqual(live.content, .empty)
        XCTAssertNil(live.liveSlideID)
    }

    @MainActor
    func testNextStartsAdvancesAndClamps() {
        let live = LiveState()
        let program = makeProgram(slideCount: 3)
        live.arm(program)

        live.next()
        XCTAssertEqual(live.liveSlideID, program[0].id)   // first press starts at 0
        live.next()
        XCTAssertEqual(live.liveSlideID, program[1].id)
        live.next()
        XCTAssertEqual(live.liveSlideID, program[2].id)
        live.next()
        XCTAssertEqual(live.liveSlideID, program[2].id)   // clamps at the end

        live.previous()
        XCTAssertEqual(live.liveSlideID, program[1].id)
    }

    @MainActor
    func testGoLiveByID() {
        let live = LiveState()
        let program = makeProgram(slideCount: 3)
        live.arm(program)
        live.goLive(id: program[2].id)
        XCTAssertEqual(live.liveSlideID, program[2].id)
    }

    @MainActor
    func testBlackPanicThenResume() {
        let live = LiveState()
        let program = makeProgram(slideCount: 2)
        live.arm(program)
        live.next()
        live.setPanic(.black)
        XCTAssertEqual(live.content, .black)
        XCTAssertNil(live.liveSlideID)
        live.next()                                       // nav key resumes
        XCTAssertEqual(live.liveSlideID, program[0].id)
    }

    @MainActor
    func testClearShowsBackgroundOnly() {
        let live = LiveState()
        live.arm(makeProgram(slideCount: 1, withText: true))
        live.next()
        live.setPanic(.clear)
        guard case .slide(let renderable) = live.content else {
            return XCTFail("expected a background-only slide")
        }
        XCTAssertTrue(renderable.elements.isEmpty)
    }

    func testSearchMatching() {
        XCTAssertTrue(LibrarySearch.matches(title: "Amazing Grace", query: ""))
        XCTAssertTrue(LibrarySearch.matches(title: "Amazing Grace", query: "grace"))
        XCTAssertTrue(LibrarySearch.matches(title: "Amazing Grace", query: "AMAZING"))
        XCTAssertFalse(LibrarySearch.matches(title: "Amazing Grace", query: "psalm"))
    }
}
