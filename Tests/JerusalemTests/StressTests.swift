import XCTest
import SwiftData
@testable import Jerusalem

/// Phase 9 soak fixture: builds a synthetic service-sized playlist and walks it
/// end-to-end through `LiveState` to flush out regressions in program building,
/// navigation clamping, content snapshotting, or prewarmer growth. Headless
/// only — the real reliability gate is a hardware dress rehearsal (see
/// `docs/DRESS-REHEARSAL.md`).
final class StressTests: XCTestCase {

    /// Builds an in-memory playlist mixing songs and (missing-file) videos so
    /// missing-media fallbacks are also exercised.
    @MainActor
    private func makeServicePlaylist(songCount: Int = 10, slidesPerSong: Int = 8,
                                     videoCount: Int = 4) throws -> Playlist {
        let container = try ModelContainer(
            for: Persistence.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let playlist = Playlist(name: "Soak")
        context.insert(playlist)

        var entryOrder = 0
        for songIndex in 0..<songCount {
            let song = Item(kind: .song, title: "Song \(songIndex)")
            song.theme = Theme.makeDefault()
            song.linesPerSlide = 2
            context.insert(song)
            ContentRebuilder.setLyrics(
                "[Verse 1]\n" + (0..<(slidesPerSong * 2)).map { "line \($0)" }.joined(separator: "\n"),
                on: song)
            let entry = PlaylistEntry(order: entryOrder); entry.item = song
            playlist.entries.append(entry); entryOrder += 1
        }
        for videoIndex in 0..<videoCount {
            let video = Item(kind: .media, title: "Clip \(videoIndex)")
            // Intentionally missing on disk — exercises the audit + fallback.
            video.mediaFilename = "missing-\(videoIndex).mp4"
            context.insert(video)
            let entry = PlaylistEntry(order: entryOrder); entry.item = video
            playlist.entries.append(entry); entryOrder += 1
        }
        return playlist
    }

    @MainActor
    func testServiceSizedProgramAdvancesWithoutCrash() throws {
        let playlist = try makeServicePlaylist()
        let program = LiveState.programSlides(for: playlist)
        // 10 songs × 8 slides (4 lines / 2-per-slide × 4 → 4 lines... actually
        // 16 lines / 2 = 8 slides) + 4 video items = 84 program items.
        XCTAssertEqual(program.count, 10 * 8 + 4)

        let live = LiveState()
        live.arm(program)

        // Walk forward 200 times; the navigator clamps at the end, so this is
        // really "drive to the end and keep mashing Next."
        for _ in 0..<200 {
            live.next()
            XCTAssertNotEqual(live.content, .empty,
                              "navigator should never bottom out into the empty state")
        }
        // Walk backward 200 times; mirror clamp on the other side.
        for _ in 0..<200 {
            live.previous()
        }
        XCTAssertEqual(live.liveSlideID, program.first?.id)
    }

    @MainActor
    func testProgramSlidesAreSnapshotsAndSurviveContainerDrop() throws {
        // Build a song, snapshot it via programSlides, then explicitly drop the
        // model context. The snapshots are value types — content must remain
        // intact for the live output to keep working through model changes.
        let snapshots: [LiveState.ProgramSlide]
        do {
            let container = try ModelContainer(
                for: Persistence.schema,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            let context = ModelContext(container)
            let song = Item(kind: .song, title: "Ephemeral")
            song.theme = Theme.makeDefault()
            song.linesPerSlide = 2
            context.insert(song)
            ContentRebuilder.setLyrics("[Verse 1]\nalpha\nbeta", on: song)
            snapshots = LiveState.programSlides(for: song)
        }   // context + container deallocate here
        XCTAssertEqual(snapshots.count, 1)
        let live = LiveState()
        live.arm(snapshots)
        live.next()
        if case .slide(let renderable) = live.content {
            XCTAssertFalse(renderable.elements.isEmpty)
        } else {
            XCTFail("expected a slide snapshot, got \(live.content)")
        }
    }

    // MARK: - SlidePrewarmer bounds

    @MainActor
    func testSlidePrewarmerEvictsBeyondLimit() {
        let prewarmer = SlidePrewarmer.shared
        prewarmer.clear()

        // 12 distinct (slide × size) combinations vs. the default limit (6).
        for n in 0..<12 {
            let slide = RenderableSlide(
                backgroundColorHex: String(format: "#%06X", n * 0x111111 % 0xFFFFFF),
                elements: [])
            _ = prewarmer.prewarm(slide, pixelSize: CGSize(width: 200, height: 112))
        }
        XCTAssertLessThanOrEqual(prewarmer.cachedCount, 6)
    }

    @MainActor
    func testSlidePrewarmerHitReturnsCachedImage() {
        let prewarmer = SlidePrewarmer.shared
        prewarmer.clear()
        let slide = RenderableSlide(backgroundColorHex: "#222222", elements: [])
        let size = CGSize(width: 160, height: 90)
        let first = prewarmer.prewarm(slide, pixelSize: size)
        let cached = prewarmer.image(for: slide, pixelSize: size)
        XCTAssertNotNil(first)
        XCTAssertNotNil(cached)
        XCTAssertTrue(first === cached)
    }
}
