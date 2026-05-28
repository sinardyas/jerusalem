import Foundation
import SwiftData

/// Central SwiftData setup: the schema and the shared, on-disk model container.
enum Persistence {
    /// All persisted model types. Listing the roots is enough — SwiftData
    /// discovers related models through relationships.
    static let schema = Schema([
        Item.self,
        Slide.self,
        SlideElement.self,
        SongSection.self,
        BibleVerse.self,
        Theme.self,
        Playlist.self,
        PlaylistEntry.self,
    ])

    /// Builds the app's model container. The main context autosaves by default, so
    /// edits are written without explicit saves — the basis for crash recovery.
    /// Main-actor-bound because seeding (Phase 6) goes through ``ContentRebuilder``,
    /// which mutates SwiftData models that the renderer reads from the main thread.
    @MainActor
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            let container = try ModelContainer(for: schema, configurations: configuration)
            let context = ModelContext(container)
            BibleSeeder.seedIfNeeded(context)   // Phase 7: bundled scripture
            SampleData.seedIfNeeded(context)
            return container
        } catch {
            fatalError("Could not create the Jerusalem model container: \(error)")
        }
    }
}
