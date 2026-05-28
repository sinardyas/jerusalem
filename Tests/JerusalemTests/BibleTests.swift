import XCTest
import SwiftData
@testable import Jerusalem

/// Phase 7 gate: an offline lookup of `John 3:16-18` produces three slides
/// (labeled with verse references, body text from the bundled scripture store)
/// and the program runs end-to-end through `LiveState` driven by `next()`.
///
/// All hardware-independent — no AppKit window, no AVFoundation playback.
final class BibleTests: XCTestCase {

    // MARK: - Catalog

    func testCatalogResolvesCanonicalAndAliases() {
        XCTAssertEqual(BibleBookCatalog.canonical(for: "John"), "John")
        XCTAssertEqual(BibleBookCatalog.canonical(for: "jn"), "John")
        XCTAssertEqual(BibleBookCatalog.canonical(for: "JOHN"), "John")
        XCTAssertEqual(BibleBookCatalog.canonical(for: " 1 cor "), "1 Corinthians")
        XCTAssertEqual(BibleBookCatalog.canonical(for: "1cor"), "1 Corinthians")
        XCTAssertEqual(BibleBookCatalog.canonical(for: "Psalm"), "Psalms")
        XCTAssertEqual(BibleBookCatalog.canonical(for: "song of songs"), "Song of Solomon")
    }

    func testCatalogRejectsUnknownBook() {
        XCTAssertNil(BibleBookCatalog.canonical(for: "Hezekiah"))
        XCTAssertNil(BibleBookCatalog.canonical(for: ""))
    }

    // MARK: - Reference parser

    func testParsesVerseRangeAndWholeChapter() throws {
        let r1 = try XCTUnwrap(BibleReferenceParser.parse("John 3:16-18"))
        XCTAssertEqual(r1.book, "John")
        XCTAssertEqual(r1.chapter, 3)
        XCTAssertEqual(r1.verses, 16...18)

        let r2 = try XCTUnwrap(BibleReferenceParser.parse("Psalm 23"))
        XCTAssertEqual(r2.book, "Psalms")
        XCTAssertEqual(r2.chapter, 23)
        XCTAssertNil(r2.verses)
    }

    func testParsesNumberedBookAndSingleVerse() throws {
        let r = try XCTUnwrap(BibleReferenceParser.parse("1 Corinthians 13:4"))
        XCTAssertEqual(r.book, "1 Corinthians")
        XCTAssertEqual(r.chapter, 13)
        XCTAssertEqual(r.verses, 4...4)
    }

    func testParserRejectsMalformedInput() {
        XCTAssertNil(BibleReferenceParser.parse(""))
        XCTAssertNil(BibleReferenceParser.parse("John"))
        XCTAssertNil(BibleReferenceParser.parse("John three"))
        XCTAssertNil(BibleReferenceParser.parse("John 3:18-16"))  // descending range
        XCTAssertNil(BibleReferenceParser.parse("Hezekiah 2:1"))
    }

    func testReferenceDisplayCanonicalizes() {
        XCTAssertEqual(BibleReferenceParser.parse("psalm 23")?.displayText, "Psalms 23")
        XCTAssertEqual(BibleReferenceParser.parse("1cor 13:4-7")?.displayText, "1 Corinthians 13:4-7")
        XCTAssertEqual(BibleReferenceParser.parse("john 3:16")?.displayText, "John 3:16")
    }

    // MARK: - Seeder + store

    @MainActor
    private func seededContainer() throws -> ModelContainer {
        let container = try ModelContainer(
            for: Persistence.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        BibleSeeder.seedIfNeeded(ModelContext(container))
        return container
    }

    @MainActor
    func testSeederLoadsStarterDatasetIdempotently() throws {
        let container = try seededContainer()
        let context = ModelContext(container)
        let firstCount = (try? context.fetchCount(FetchDescriptor<BibleVerse>())) ?? 0
        XCTAssertGreaterThan(firstCount, 0, "starter dataset must populate the store")

        // Second call is a no-op (idempotent).
        BibleSeeder.seedIfNeeded(context)
        let secondCount = (try? context.fetchCount(FetchDescriptor<BibleVerse>())) ?? 0
        XCTAssertEqual(secondCount, firstCount)
    }

    @MainActor
    func testStoreReturnsVerseRange() throws {
        let context = ModelContext(try seededContainer())
        let reference = try XCTUnwrap(BibleReferenceParser.parse("John 3:16-18"))
        let verses = BibleStore.verses(for: reference, translation: "kjv", in: context)
        XCTAssertEqual(verses.map(\.number), [16, 17, 18])
        XCTAssertEqual(verses.first?.book, "John")
        XCTAssertFalse(verses.first?.text.isEmpty ?? true)
    }

    @MainActor
    func testStoreReturnsWholeChapter() throws {
        let context = ModelContext(try seededContainer())
        let reference = try XCTUnwrap(BibleReferenceParser.parse("Psalm 23"))
        let verses = BibleStore.verses(for: reference, translation: "kjv", in: context)
        XCTAssertEqual(verses.map(\.number), Array(1...6))
    }

    @MainActor
    func testStoreReturnsWebTranslationSeparately() throws {
        let context = ModelContext(try seededContainer())
        let reference = try XCTUnwrap(BibleReferenceParser.parse("John 3:16"))
        let kjv = BibleStore.verses(for: reference, translation: "kjv", in: context)
        let web = BibleStore.verses(for: reference, translation: "web", in: context)
        XCTAssertEqual(kjv.count, 1)
        XCTAssertEqual(web.count, 1)
        XCTAssertNotEqual(kjv.first?.text, web.first?.text)
    }

    @MainActor
    func testUnknownReferenceReturnsEmpty() throws {
        let context = ModelContext(try seededContainer())
        // Genesis isn't in the starter dataset; the store should just shrug.
        let reference = try XCTUnwrap(BibleReferenceParser.parse("Genesis 1:1"))
        XCTAssertTrue(BibleStore.verses(for: reference, translation: "kjv", in: context).isEmpty)
    }

    // MARK: - Splitter

    @MainActor
    func testBibleSplitYieldsOneSlidePerVerseWithReferenceFooter() throws {
        let context = ModelContext(try seededContainer())
        let reference = try XCTUnwrap(BibleReferenceParser.parse("John 3:16-17"))
        let verses = BibleStore.verses(for: reference, translation: "kjv", in: context)
        let drafts = SlideSplitter.split(bibleVerses: verses, translation: "kjv")
        XCTAssertEqual(drafts.count, 2)
        XCTAssertEqual(drafts[0].sectionLabel, "John 3:16")
        XCTAssertEqual(drafts[1].sectionLabel, "John 3:17")
        XCTAssertTrue(drafts[0].text.contains("— John 3:16 (KJV)"))
    }

    // MARK: - Phase 7 gate: reference → slides → keyboard run-through

    @MainActor
    func testEnterReferenceOfflineRunsThroughKeyboard() throws {
        let container = try seededContainer()
        let context = ModelContext(container)

        let passage = Item(kind: .bible, title: "Sunday reading")
        passage.theme = Theme.makeDefault()
        passage.linesPerSlide = 2
        context.insert(passage)

        // User types `John 3:16-18` in the editor; setBibleReference fetches + builds.
        ContentRebuilder.setBibleReference("John 3:16-18", translation: "kjv", on: passage)

        XCTAssertEqual(passage.orderedSlides.count, 3)
        XCTAssertEqual(passage.orderedSlides.map(\.sectionLabel),
                       ["John 3:16", "John 3:17", "John 3:18"])
        let firstSlideText = try XCTUnwrap(passage.orderedSlides.first?.orderedElements.first?.text)
        XCTAssertTrue(firstSlideText.contains("loved the world"))
        XCTAssertTrue(firstSlideText.contains("(KJV)"))

        // Reference canonicalises: editor stores back what we looked up.
        XCTAssertEqual(passage.bibleReference, "John 3:16-18")

        // Keyboard run-through — the actual gate.
        let live = LiveState()
        let program = LiveState.programSlides(for: passage)
        XCTAssertEqual(program.count, 3)
        live.arm(program)

        live.next()
        XCTAssertEqual(live.liveSlideID, program[0].id)
        live.next()
        XCTAssertEqual(live.liveSlideID, program[1].id)
        live.next()
        XCTAssertEqual(live.liveSlideID, program[2].id)
    }

    @MainActor
    func testUnknownReferenceClearsSlides() throws {
        let context = ModelContext(try seededContainer())
        let passage = Item(kind: .bible, title: "test")
        passage.theme = Theme.makeDefault()
        passage.linesPerSlide = 2
        context.insert(passage)

        ContentRebuilder.setBibleReference("John 3:16-18", translation: "kjv", on: passage)
        XCTAssertEqual(passage.orderedSlides.count, 3)

        // Re-point at a reference we don't have data for — slides should clear.
        ContentRebuilder.setBibleReference("Genesis 1:1", translation: "kjv", on: passage)
        XCTAssertEqual(passage.orderedSlides.count, 0)

        // And a malformed input also clears without crashing.
        ContentRebuilder.setBibleReference("not a reference", translation: "kjv", on: passage)
        XCTAssertEqual(passage.orderedSlides.count, 0)
    }
}
