import XCTest
import SwiftData
@testable import Jerusalem

/// Playlist-management gate: the pure ``PlaylistEditing`` math (order assignment,
/// reorder, removal, default naming) plus a persistence round-trip proving entry
/// order survives a reopen and that deleting a playlist cascade-deletes its
/// entries while leaving the shared items intact.
final class PlaylistEditingTests: XCTestCase {

    // MARK: - nextOrder

    func testNextOrderOnEmptyIsZero() {
        XCTAssertEqual(PlaylistEditing.nextOrder(in: []), 0)
    }

    func testNextOrderIsMaxPlusOne() {
        let entries = [PlaylistEntry(order: 0), PlaylistEntry(order: 1), PlaylistEntry(order: 2)]
        XCTAssertEqual(PlaylistEditing.nextOrder(in: entries), 3)
        // Robust to gaps / non-contiguous orders.
        XCTAssertEqual(PlaylistEditing.nextOrder(in: [PlaylistEntry(order: 5)]), 6)
    }

    // MARK: - makeEntry

    func testMakeEntryLinksAndAppendsAtNextOrder() {
        let playlist = Playlist(name: "Sunday AM")
        let song = Item(kind: .song, title: "Amazing Grace")
        let bible = Item(kind: .bible, title: "John 3:16")

        let first = PlaylistEditing.makeEntry(for: song, in: playlist)
        XCTAssertEqual(first.order, 0)
        XCTAssertTrue(first.item === song)
        XCTAssertTrue(first.playlist === playlist)
        XCTAssertEqual(playlist.entries.count, 1)

        let second = PlaylistEditing.makeEntry(for: bible, in: playlist)
        XCTAssertEqual(second.order, 1)
        XCTAssertEqual(playlist.orderedEntries.map { $0.item?.title }, ["Amazing Grace", "John 3:16"])
    }

    // MARK: - reorder

    /// Dragging the last entry to the top makes it order 0 and shifts the rest down,
    /// staying gapless (top = first).
    func testReorderRewritesOrderForwardGapless() {
        let a = PlaylistEntry(order: 0)
        let b = PlaylistEntry(order: 1)
        let c = PlaylistEntry(order: 2)
        // Running order [a, b, c]; drag c (index 2) to the top (0) → [c, a, b].
        PlaylistEditing.reorder([a, b, c], from: IndexSet(integer: 2), to: 0)
        XCTAssertEqual(c.order, 0)
        XCTAssertEqual(a.order, 1)
        XCTAssertEqual(b.order, 2)
    }

    func testReorderMovesTopEntryDown() {
        let a = PlaylistEntry(order: 0)
        let b = PlaylistEntry(order: 1)
        let c = PlaylistEntry(order: 2)
        // Drag a (index 0) to the end → [b, c, a].
        PlaylistEditing.reorder([a, b, c], from: IndexSet(integer: 0), to: 3)
        XCTAssertEqual(b.order, 0)
        XCTAssertEqual(c.order, 1)
        XCTAssertEqual(a.order, 2)
    }

    // MARK: - remove

    func testRemoveDropsEntryAndRenumbersGapless() {
        let playlist = Playlist(name: "Set")
        let entries = (0..<3).map { i -> PlaylistEntry in
            let e = PlaylistEntry(order: i)
            e.playlist = playlist
            return e
        }
        playlist.entries = entries

        PlaylistEditing.remove(entries[1], from: playlist)   // remove the middle one
        XCTAssertEqual(playlist.entries.count, 2)
        XCTAssertFalse(playlist.entries.contains { $0 === entries[1] })
        XCTAssertEqual(playlist.orderedEntries.map(\.order), [0, 1], "remaining orders stay gapless")
        XCTAssertTrue(playlist.orderedEntries.first === entries[0])
        XCTAssertTrue(playlist.orderedEntries.last === entries[2])
    }

    // MARK: - defaultPlaylistName

    func testDefaultPlaylistNameDedupes() {
        XCTAssertEqual(PlaylistEditing.defaultPlaylistName(existing: []), "Untitled Playlist")
        let one = [Playlist(name: "Untitled Playlist")]
        XCTAssertEqual(PlaylistEditing.defaultPlaylistName(existing: one), "Untitled Playlist 2")
        let two = [Playlist(name: "Untitled Playlist"), Playlist(name: "Untitled Playlist 2")]
        XCTAssertEqual(PlaylistEditing.defaultPlaylistName(existing: two), "Untitled Playlist 3")
        // Unrelated names don't shadow the base.
        XCTAssertEqual(PlaylistEditing.defaultPlaylistName(existing: [Playlist(name: "Sunday AM")]),
                       "Untitled Playlist")
    }

    // MARK: - Persistence round-trip

    /// Reorder persists across a reopen, and deleting a playlist cascade-deletes
    /// its `PlaylistEntry` rows but leaves the shared `Item` rows intact.
    func testReorderPersistsAndDeleteKeepsItems() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("jerusalem-\(UUID().uuidString).store")
        addTeardownBlock {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
            }
        }
        let configuration = ModelConfiguration(schema: Persistence.schema, url: url)

        // Session 1 — two items in a playlist, then reverse their order.
        do {
            let container = try ModelContainer(for: Persistence.schema, configurations: configuration)
            let context = ModelContext(container)

            let a = Item(kind: .song, title: "First")
            let b = Item(kind: .song, title: "Second")
            context.insert(a)
            context.insert(b)

            let playlist = Playlist(name: "Service")
            context.insert(playlist)
            PlaylistEditing.makeEntry(for: a, in: playlist)
            PlaylistEditing.makeEntry(for: b, in: playlist)

            // Reverse: [a, b] → [b, a].
            PlaylistEditing.reorder(playlist.orderedEntries, from: IndexSet(integer: 1), to: 0)
            try context.save()
        }

        // Session 2 — reopen; the reversed order is restored.
        do {
            let container = try ModelContainer(for: Persistence.schema, configurations: configuration)
            let context = ModelContext(container)

            let playlist = try XCTUnwrap(try context.fetch(FetchDescriptor<Playlist>()).first)
            XCTAssertEqual(playlist.orderedEntries.map { $0.item?.title }, ["Second", "First"])
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<PlaylistEntry>()), 2)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<Item>()), 2)

            // Delete the playlist — entries cascade away, items survive.
            context.delete(playlist)
            try context.save()
        }

        // Session 3 — entries are gone, both items remain.
        let container = try ModelContainer(for: Persistence.schema, configurations: configuration)
        let context = ModelContext(container)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Playlist>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PlaylistEntry>()), 0,
                       "deleting a playlist cascade-deletes its entries")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Item>()), 2,
                       "shared items are NOT deleted with the playlist")
    }

    // MARK: - groupedProgram

    /// One group per entry, in running order, with the entry's item title and its
    /// slides; flattening the groups equals the flat armed program (same ids/order),
    /// so click-to-go-live in the grouped grid lines up with the live program.
    @MainActor
    func testGroupedProgramOneGroupPerEntryMatchesFlatProgram() {
        let container = Persistence.makeContainer(inMemory: true)
        let context = container.mainContext

        func makeSong(_ title: String, slides count: Int) -> Item {
            let item = Item(kind: .song, title: title)
            item.slides = (0..<count).map { i in
                let slide = Slide(order: i, sectionLabel: "Verse \(i + 1)")
                slide.elements = [SlideElement(kind: .text, text: "line \(i)")]
                return slide
            }
            context.insert(item)
            return item
        }

        let a = makeSong("First", slides: 2)
        let b = makeSong("Second", slides: 3)

        let playlist = Playlist(name: "Service")
        context.insert(playlist)
        PlaylistEditing.makeEntry(for: a, in: playlist)
        PlaylistEditing.makeEntry(for: b, in: playlist)

        let groups = LiveState.groupedProgram(for: playlist)
        XCTAssertEqual(groups.map(\.title), ["First", "Second"])
        XCTAssertEqual(groups.map { $0.slides.count }, [2, 3])
        XCTAssertEqual(groups.flatMap(\.slides).map(\.id),
                       LiveState.programSlides(for: playlist).map(\.id),
                       "flattened groups == flat program, same order/ids")
    }

    /// The same item in two entries forms two distinct groups (keyed on entry id).
    @MainActor
    func testGroupedProgramDuplicateItemFormsTwoGroups() {
        let container = Persistence.makeContainer(inMemory: true)
        let context = container.mainContext

        let song = Item(kind: .song, title: "Repeat")
        song.slides = [Slide(order: 0, sectionLabel: "V1")]
        context.insert(song)

        let playlist = Playlist(name: "Set")
        context.insert(playlist)
        PlaylistEditing.makeEntry(for: song, in: playlist)
        PlaylistEditing.makeEntry(for: song, in: playlist)

        let groups = LiveState.groupedProgram(for: playlist)
        XCTAssertEqual(groups.count, 2, "same item in two entries → two groups")
        XCTAssertEqual(groups.map(\.title), ["Repeat", "Repeat"])
        XCTAssertNotEqual(groups[0].id, groups[1].id, "groups keyed on distinct entry ids")
    }
}
