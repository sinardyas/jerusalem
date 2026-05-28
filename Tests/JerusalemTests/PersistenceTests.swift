import XCTest
import SwiftData
@testable import Jerusalem

/// Phase 1 gate: proves the SwiftData layer persists and fully restores state
/// across a container reopen — the programmatic equivalent of "quit and relaunch."
final class PersistenceTests: XCTestCase {

    func testSongAndPlaylistPersistAcrossReopen() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("jerusalem-\(UUID().uuidString).store")
        addTeardownBlock {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(
                    at: URL(fileURLWithPath: url.path + suffix))
            }
        }
        let configuration = ModelConfiguration(schema: Persistence.schema, url: url)

        // Session 1 — insert a song (with a slide) and a playlist that references it.
        do {
            let container = try ModelContainer(for: Persistence.schema, configurations: configuration)
            let context = ModelContext(container)

            let song = Item(kind: .song, title: "Test Song", subtitle: "Tester")
            let slide = Slide(order: 0, sectionLabel: "Verse 1")
            slide.elements = [SlideElement(kind: .text, text: "a line of lyrics")]
            song.slides = [slide]
            context.insert(song)

            let playlist = Playlist(name: "Test Playlist")
            let entry = PlaylistEntry(order: 0)
            entry.item = song
            playlist.entries = [entry]
            context.insert(playlist)

            try context.save()
        }

        // Session 2 — reopen the same on-disk store; everything should be restored.
        let container = try ModelContainer(for: Persistence.schema, configurations: configuration)
        let context = ModelContext(container)

        let items = try context.fetch(FetchDescriptor<Item>())
        XCTAssertEqual(items.count, 1)
        let song = try XCTUnwrap(items.first)
        XCTAssertEqual(song.title, "Test Song")
        XCTAssertEqual(song.kind, .song)
        XCTAssertEqual(song.orderedSlides.count, 1)
        XCTAssertEqual(song.orderedSlides.first?.orderedElements.first?.text, "a line of lyrics")

        let playlists = try context.fetch(FetchDescriptor<Playlist>())
        XCTAssertEqual(playlists.count, 1)
        let playlist = try XCTUnwrap(playlists.first)
        XCTAssertEqual(playlist.name, "Test Playlist")
        XCTAssertEqual(playlist.orderedEntries.first?.item?.title, "Test Song")
    }

    @MainActor
    func testSeedingPopulatesEmptyStoreExactlyOnce() throws {
        let container = try ModelContainer(
            for: Persistence.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)

        SampleData.seedIfNeeded(context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Item>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Playlist>()), 1)

        // Idempotent: a second call must not duplicate the sample data.
        SampleData.seedIfNeeded(context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Item>()), 1)
    }
}
