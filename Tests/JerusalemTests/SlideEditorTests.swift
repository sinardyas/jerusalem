import XCTest
import SwiftData
@testable import Jerusalem

/// Phase 8 gate (Part 1, headless): the pure geometry rules behind the slide
/// editor, plus the rebuilder's "yield to manual edits" guarantee.
///
/// The UX gate — "non-designer designs a good-looking slide in under a minute"
/// — still needs a real-hardware run; this suite only covers what XCTest can
/// observe (snap math, clamp math, layer reorder, rebuild skip, element CRUD).
final class SlideEditorTests: XCTestCase {

    // MARK: - SlideGeometry: clamping

    func testClampedStaysInsideZeroToOneWithMinimumSize() {
        let tiny = SlideGeometry.clamped(.init(x: -0.2, y: 1.5, width: 0.01, height: 2.0))
        XCTAssertGreaterThanOrEqual(tiny.x, 0)
        XCTAssertGreaterThanOrEqual(tiny.y, 0)
        XCTAssertGreaterThanOrEqual(tiny.width, 0.05)
        XCTAssertGreaterThanOrEqual(tiny.height, 0.05)
        XCTAssertLessThanOrEqual(tiny.maxX, 1.0)
        XCTAssertLessThanOrEqual(tiny.maxY, 1.0)
    }

    // MARK: - SlideGeometry: snap-to-grid

    func testSnappedRoundsToNearestGridStep() {
        XCTAssertEqual(SlideGeometry.snapped(0.12, step: 0.05, enabled: true), 0.10, accuracy: 1e-9)
        XCTAssertEqual(SlideGeometry.snapped(0.13, step: 0.05, enabled: true), 0.15, accuracy: 1e-9)
        XCTAssertEqual(SlideGeometry.snapped(0.12, step: 0.05, enabled: false), 0.12, accuracy: 1e-9)
    }

    func testSnappedFrameMaintainsMinimumDimensions() {
        let snapped = SlideGeometry.snappedToGrid(
            .init(x: 0.07, y: 0.09, width: 0.32, height: 0.01),
            step: 0.05, enabled: true)
        XCTAssertEqual(snapped.x, 0.05, accuracy: 1e-9)
        XCTAssertEqual(snapped.y, 0.10, accuracy: 1e-9)
        XCTAssertEqual(snapped.width, 0.30, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(snapped.height, 0.05)
    }

    // MARK: - SlideGeometry: drag + handle math

    func testBodyDragMovesWithoutChangingSize() {
        let start = SlideGeometry.Frame(x: 0.10, y: 0.20, width: 0.30, height: 0.40)
        let dragged = SlideGeometry.dragged(start, by: 0.05, dy: -0.02, handle: .body)
        XCTAssertEqual(dragged.x, 0.15, accuracy: 1e-9)
        XCTAssertEqual(dragged.y, 0.18, accuracy: 1e-9)
        XCTAssertEqual(dragged.width, 0.30, accuracy: 1e-9)
        XCTAssertEqual(dragged.height, 0.40, accuracy: 1e-9)
    }

    func testTopLeftHandleResizesUpAndLeft() {
        let start = SlideGeometry.Frame(x: 0.20, y: 0.30, width: 0.40, height: 0.30)
        let dragged = SlideGeometry.dragged(start, by: -0.05, dy: -0.10, handle: .topLeft)
        XCTAssertEqual(dragged.x, 0.15, accuracy: 1e-9)
        XCTAssertEqual(dragged.y, 0.20, accuracy: 1e-9)
        XCTAssertEqual(dragged.width, 0.45, accuracy: 1e-9)
        XCTAssertEqual(dragged.height, 0.40, accuracy: 1e-9)
    }

    func testBottomRightHandleResizesDownAndRight() {
        let start = SlideGeometry.Frame(x: 0.20, y: 0.30, width: 0.40, height: 0.30)
        let dragged = SlideGeometry.dragged(start, by: 0.10, dy: 0.05, handle: .bottomRight)
        XCTAssertEqual(dragged.x, 0.20, accuracy: 1e-9)
        XCTAssertEqual(dragged.y, 0.30, accuracy: 1e-9)
        XCTAssertEqual(dragged.width, 0.50, accuracy: 1e-9)
        XCTAssertEqual(dragged.height, 0.35, accuracy: 1e-9)
    }

    // MARK: - SlideGeometry: alignment guides

    func testAlignmentCandidatesIncludeSlideAndOtherElements() {
        let other = SlideGeometry.Frame(x: 0.20, y: 0.30, width: 0.40, height: 0.30)
        let candidates = SlideGeometry.alignmentCandidates(against: [other])
        XCTAssertTrue(approximatelyContains(candidates.verticals, 0))
        XCTAssertTrue(approximatelyContains(candidates.verticals, 0.5))
        XCTAssertTrue(approximatelyContains(candidates.verticals, 1))
        XCTAssertTrue(approximatelyContains(candidates.verticals, 0.20))    // other.minX
        XCTAssertTrue(approximatelyContains(candidates.verticals, 0.40))    // other.centerX
        XCTAssertTrue(approximatelyContains(candidates.verticals, 0.60))    // other.maxX (= 0.20 + 0.40, FP-noisy)
    }

    /// `[Double].contains(_:Element)` does an exact `==`, but the candidates
    /// pass through `x + width` and friends — FP arithmetic that won't compare
    /// equal to the same literal in the test. Tolerance match is what we want.
    private func approximatelyContains(_ values: [Double], _ target: Double,
                                       tolerance: Double = 1e-9) -> Bool {
        values.contains { abs($0 - target) < tolerance }
    }

    func testSnapVerticalCatchesNearbyCenter() {
        let candidates = SlideGeometry.alignmentCandidates(against: [])
        let near = SlideGeometry.Frame(x: 0.39, y: 0.10, width: 0.22, height: 0.10)
        let snap = SlideGeometry.snapVertical(frame: near, candidates: candidates)
        // centerX = 0.50 = slide center → caught by .center anchor.
        XCTAssertNotNil(snap)
        XCTAssertEqual(snap?.line, 0.5)
        XCTAssertEqual(snap?.anchor, .center)
    }

    func testSnapVerticalIgnoresFarAnchors() {
        let candidates = SlideGeometry.alignmentCandidates(against: [])
        let far = SlideGeometry.Frame(x: 0.20, y: 0.10, width: 0.10, height: 0.10)
        XCTAssertNil(SlideGeometry.snapVertical(frame: far, candidates: candidates))
    }

    // MARK: - SlideGeometry: layer order

    func testRaiseSwapsWithNeighborAndClampsAtTop() {
        XCTAssertEqual(SlideGeometry.raised(2, in: [1, 2, 3]), [1, 3, 2])
        XCTAssertEqual(SlideGeometry.raised(3, in: [1, 2, 3]), [1, 2, 3])   // top already
        XCTAssertEqual(SlideGeometry.raised(9, in: [1, 2, 3]), [1, 2, 3])   // not present
    }

    func testLowerMirrorsRaise() {
        XCTAssertEqual(SlideGeometry.lowered(2, in: [1, 2, 3]), [2, 1, 3])
        XCTAssertEqual(SlideGeometry.lowered(1, in: [1, 2, 3]), [1, 2, 3])   // bottom already
    }

    func testMoveToFrontAndBackSendsItemToEnds() {
        XCTAssertEqual(SlideGeometry.movedToFront(1, in: [1, 2, 3]), [2, 3, 1])
        XCTAssertEqual(SlideGeometry.movedToBack(3, in: [1, 2, 3]), [3, 1, 2])
        // no-op if absent
        XCTAssertEqual(SlideGeometry.movedToFront(9, in: [1, 2, 3]), [1, 2, 3])
        XCTAssertEqual(SlideGeometry.movedToBack(9, in: [1, 2, 3]), [1, 2, 3])
        // no-op if already at the target end
        XCTAssertEqual(SlideGeometry.movedToFront(3, in: [1, 2, 3]), [1, 2, 3])
        XCTAssertEqual(SlideGeometry.movedToBack(1, in: [1, 2, 3]), [1, 2, 3])
    }

    // MARK: - Rebuilder: manual-edit yield

    @MainActor
    func testRebuilderYieldsToManuallyEditedSlides() throws {
        let container = try ModelContainer(
            for: Persistence.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)

        let song = Item(kind: .song, title: "Test")
        song.theme = Theme.makeDefault()
        song.linesPerSlide = 2
        context.insert(song)

        ContentRebuilder.setLyrics("[Verse 1]\na\nb\nc\nd", on: song)
        XCTAssertEqual(song.orderedSlides.count, 2)

        // Pretend the user edited slide 0 in the WYSIWYG editor.
        let editedText = "EDITED"
        song.orderedSlides.first?.orderedElements.first?.text = editedText
        song.orderedSlides.first?.isManuallyEdited = true

        // Re-running the rebuilder — even a full reset — must NOT clobber edits.
        ContentRebuilder.rebuild(song)
        XCTAssertEqual(song.orderedSlides.count, 2)
        XCTAssertEqual(song.orderedSlides.first?.orderedElements.first?.text, editedText)

        // A song whose slides are *not* manually edited still rebuilds normally.
        let untouched = Item(kind: .song, title: "Untouched")
        untouched.theme = Theme.makeDefault()
        untouched.linesPerSlide = 2
        context.insert(untouched)
        ContentRebuilder.setLyrics("[Verse 1]\na\nb", on: untouched)
        XCTAssertEqual(untouched.orderedSlides.count, 1)
        untouched.linesPerSlide = 1
        ContentRebuilder.rebuild(untouched)
        XCTAssertEqual(untouched.orderedSlides.count, 2)
    }
}
