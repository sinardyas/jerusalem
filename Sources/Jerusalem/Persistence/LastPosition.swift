import Foundation
import SwiftData

/// Reopens-where-you-left-off support. We persist the *operator's selection*
/// (which item or playlist was armed when the app last closed), not the live
/// position inside the program — the user explicitly starts playback on launch,
/// so auto-resuming a live slide would be surprising.
///
/// The persisted handle is the stable ``Item.uuid`` / ``Playlist.uuid`` rather
/// than SwiftData's `PersistentIdentifier`, which is process-local and
/// regenerated on relaunch.
enum LastPosition {

    private static let key = "jerusalem.lastSelection.v1"

    /// What was selected — an item or a playlist, by their stable UUID.
    enum Selection: Codable, Equatable, Sendable {
        case item(UUID)
        case playlist(UUID)
    }

    static func save(_ selection: Selection?) {
        let defaults = UserDefaults.standard
        guard let selection else {
            defaults.removeObject(forKey: key)
            return
        }
        if let data = try? JSONEncoder().encode(selection) {
            defaults.set(data, forKey: key)
        }
    }

    static func load() -> Selection? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let selection = try? JSONDecoder().decode(Selection.self, from: data)
        else { return nil }
        return selection
    }

    /// Resolves a stored selection back to a SwiftData `PersistentIdentifier`
    /// the operator can hand to its `@State selectedID`. Returns nil if the
    /// referenced row was deleted while the app was closed.
    @MainActor
    static func resolve(_ selection: Selection?,
                        in context: ModelContext) -> PersistentIdentifier? {
        guard let selection else { return nil }
        switch selection {
        case .item(let uuid):
            var descriptor = FetchDescriptor<Item>(
                predicate: #Predicate { $0.uuid == uuid })
            descriptor.fetchLimit = 1
            return (try? context.fetch(descriptor))?.first?.persistentModelID
        case .playlist(let uuid):
            var descriptor = FetchDescriptor<Playlist>(
                predicate: #Predicate { $0.uuid == uuid })
            descriptor.fetchLimit = 1
            return (try? context.fetch(descriptor))?.first?.persistentModelID
        }
    }
}
