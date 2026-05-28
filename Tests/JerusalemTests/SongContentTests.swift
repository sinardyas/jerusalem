import XCTest
import SwiftData
@testable import Jerusalem

/// Phase 6 gate: a lyrics block with `[Verse 1]` / `[Chorus]` markers turns into
/// well-labeled slides via the same path the in-app editor uses, and that program
/// runs end to end through `LiveState` (the keyboard-driver from Phase 4).
///
/// Hardware-independent: every assertion lives in the parser, the splitter, the
/// rebuilder, or `LiveState` — no AppKit window, no AVFoundation playback.
final class SongContentTests: XCTestCase {

    // MARK: - Parser

    func testParsesNumberedAndUnnumberedMarkers() {
        let lyrics = """
        [Verse 1]
        line one
        line two
        [Chorus]
        my chains are gone
        """
        let sections = SongLyricsParser.parse(lyrics)
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0].kind, .verse)
        XCTAssertEqual(sections[0].number, 1)
        XCTAssertEqual(sections[0].lyrics, "line one\nline two")
        XCTAssertEqual(sections[1].kind, .chorus)
        XCTAssertNil(sections[1].number)
        XCTAssertEqual(sections[1].lyrics, "my chains are gone")
    }

    func testMarkersAreCaseInsensitive() {
        let sections = SongLyricsParser.parse("[VERSE 2]\nfoo\n[ chorus ]\nbar")
        XCTAssertEqual(sections.map(\.kind), [.verse, .chorus])
        XCTAssertEqual(sections[0].number, 2)
    }

    func testBareLyricsBecomeASingleVerse() {
        let sections = SongLyricsParser.parse("just\ntwo lines")
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].kind, .verse)
        XCTAssertNil(sections[0].number)
        XCTAssertEqual(sections[0].lyrics, "just\ntwo lines")
    }

    func testUnknownBracketLineIsNotAMarker() {
        // `[Refrain]` isn't in the MVP vocabulary, so it should NOT split sections
        // — the line gets treated as content.
        let sections = SongLyricsParser.parse("[Refrain]\nsing it")
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].kind, .verse)
        XCTAssertTrue(sections[0].lyrics.contains("[Refrain]"))
    }

    func testFormatRoundTripsBackThroughParser() {
        let original = SongLyricsParser.parse("[Verse 1]\na\nb\n\n[Chorus]\nc")
        let formatted = SongLyricsParser.format(original)
        XCTAssertEqual(SongLyricsParser.parse(formatted), original)
    }

    // MARK: - Splitter

    func testSplitterHonorsLinesPerSlide() {
        let section = ParsedSongSection(kind: .verse, number: 1,
                                        lyrics: "l1\nl2\nl3\nl4\nl5")
        let drafts = SlideSplitter.split(songSections: [section], linesPerSlide: 2)
        XCTAssertEqual(drafts.count, 3)
        XCTAssertEqual(drafts[0].text, "l1\nl2")
        XCTAssertEqual(drafts[1].text, "l3\nl4")
        XCTAssertEqual(drafts[2].text, "l5")
    }

    func testOnlyFirstSlideOfSectionGetsTheLabel() {
        let section = ParsedSongSection(kind: .verse, number: 1,
                                        lyrics: "a\nb\nc\nd")
        let drafts = SlideSplitter.split(songSections: [section], linesPerSlide: 2)
        XCTAssertEqual(drafts[0].sectionLabel, "Verse 1")
        XCTAssertNil(drafts[1].sectionLabel)
    }

    func testSermonSplitProducesTitleAndPointSlides() {
        let drafts = SlideSplitter.split(
            sermonTitle: "Grace Abounds",
            body: "First point.\n\nSecond point continues\nover two lines.\n\nThird.",
            linesPerSlide: 2)
        XCTAssertEqual(drafts.first?.sectionLabel, "Title")
        XCTAssertEqual(drafts.first?.text, "Grace Abounds")
        XCTAssertEqual(drafts.dropFirst().map(\.sectionLabel),
                       ["Point 1", "Point 2", "Point 3"])
    }

    // MARK: - Rebuilder + live program (the actual gate)

    @MainActor
    func testEditingLyricsRebuildsSlidesAndDrivesLiveProgram() throws {
        let container = try ModelContainer(
            for: Persistence.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)

        let song = Item(kind: .song, title: "Amazing Grace")
        song.theme = Theme.makeDefault()
        song.linesPerSlide = 2
        context.insert(song)

        ContentRebuilder.setLyrics("""
            [Verse 1]
            Amazing grace! How sweet the sound
            That saved a wretch like me!
            I once was lost, but now am found;
            Was blind, but now I see.

            [Chorus]
            My chains are gone, I’ve been set free
            My God, my Savior has ransomed me
            """, on: song)

        // Two verses × 2 lines / 2-per-slide = 2 slides, plus 2 chorus lines / 2 = 1.
        XCTAssertEqual(song.orderedSlides.count, 3)
        XCTAssertEqual(song.orderedSlides.map(\.sectionLabel),
                       ["Verse 1", nil, "Chorus"])
        XCTAssertEqual(song.orderedSlides[0].orderedElements.first?.text,
                       "Amazing grace! How sweet the sound\nThat saved a wretch like me!")

        // Keyboard run-through: arm + step the program; LiveState surfaces each slide.
        let live = LiveState()
        let program = LiveState.programSlides(for: song)
        XCTAssertEqual(program.count, 3)
        live.arm(program)

        live.next()                              // first press starts at slide 0
        XCTAssertEqual(live.liveSlideID, program[0].id)
        live.next()
        XCTAssertEqual(live.liveSlideID, program[1].id)
        live.next()
        XCTAssertEqual(live.liveSlideID, program[2].id)
    }

    @MainActor
    func testChangingLinesPerSlideRebuildsWithoutLosingLyrics() throws {
        let container = try ModelContainer(
            for: Persistence.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)

        let song = Item(kind: .song, title: "Test")
        song.theme = Theme.makeDefault()
        song.linesPerSlide = 4
        context.insert(song)
        ContentRebuilder.setLyrics("[Verse 1]\na\nb\nc\nd", on: song)
        XCTAssertEqual(song.orderedSlides.count, 1)

        song.linesPerSlide = 2
        ContentRebuilder.rebuild(song)
        XCTAssertEqual(song.orderedSlides.count, 2)
        // The authored lyrics survive a re-split — that's the value of keeping
        // SongSection rows as the source of truth.
        XCTAssertEqual(song.orderedSongSections.first?.lyrics, "a\nb\nc\nd")
    }

    @MainActor
    func testSermonRebuildProducesTitleThenPoints() throws {
        let container = try ModelContainer(
            for: Persistence.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)

        let sermon = Item(kind: .text, title: "Grace Abounds")
        sermon.theme = Theme.makeDefault()
        sermon.linesPerSlide = 3
        context.insert(sermon)

        ContentRebuilder.setBody("First.\n\nSecond.\n\nThird.", on: sermon)

        XCTAssertEqual(sermon.orderedSlides.map(\.sectionLabel),
                       ["Title", "Point 1", "Point 2", "Point 3"])
        XCTAssertEqual(sermon.orderedSlides.first?.orderedElements.first?.text,
                       "Grace Abounds")
    }

    @MainActor
    func testRebuiltSlideUsesItemTheme() throws {
        let container = try ModelContainer(
            for: Persistence.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)

        let song = Item(kind: .song, title: "Test")
        let theme = Theme.makeDefault()
        theme.backgroundColorHex = "#112233"
        theme.fontName = "Helvetica"
        theme.fontSize = 64
        theme.textColorHex = "#ABCDEF"
        song.theme = theme
        song.linesPerSlide = 2
        context.insert(song)
        ContentRebuilder.setLyrics("just a line", on: song)

        let slide = try XCTUnwrap(song.orderedSlides.first)
        XCTAssertEqual(slide.backgroundColorHex, "#112233")
        let element = try XCTUnwrap(slide.orderedElements.first)
        XCTAssertEqual(element.fontName, "Helvetica")
        XCTAssertEqual(element.fontSize, 64)
        XCTAssertEqual(element.colorHex, "#ABCDEF")
    }
}
