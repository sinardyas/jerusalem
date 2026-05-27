import Foundation
import SwiftData

/// A named, ordered, savable set of items for a service or purpose
/// (e.g. "Sunday AM"). The unified replacement for the old "setlist" concept;
/// a looping playlist doubles as a pre-service loop.
@Model
final class Playlist {
    var uuid: UUID = UUID()
    var name: String = "Untitled Playlist"
    var createdAt: Date = Date.now
    var loops: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \PlaylistEntry.playlist)
    var entries: [PlaylistEntry] = []

    init(name: String, loops: Bool = false) {
        self.name = name
        self.loops = loops
    }

    /// Entries in running order.
    var orderedEntries: [PlaylistEntry] {
        entries.sorted { $0.order < $1.order }
    }
}

/// Join model giving each item a position within a specific playlist. An item can
/// appear in many playlists, each with its own ordering.
@Model
final class PlaylistEntry {
    var order: Int = 0
    var item: Item?
    var playlist: Playlist?

    init(order: Int) {
        self.order = order
    }
}
