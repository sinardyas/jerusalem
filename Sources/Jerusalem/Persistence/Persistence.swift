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
        Theme.self,
        Playlist.self,
        PlaylistEntry.self,
    ])

    /// Builds the app's model container. The main context autosaves by default, so
    /// edits are written without explicit saves — the basis for crash recovery.
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            let container = try ModelContainer(for: schema, configurations: configuration)
            SampleData.seedIfNeeded(ModelContext(container))
            return container
        } catch {
            fatalError("Could not create the Jerusalem model container: \(error)")
        }
    }
}
