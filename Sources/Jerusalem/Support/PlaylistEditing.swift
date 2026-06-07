import Foundation

/// Pure playlist-editing math — order assignment, reorder, removal, and default
/// naming — extracted so it's unit-testable without UI or a `ModelContext`.
/// Mirrors ``LibrarySearch`` and ``SlideLayers``: the view stays a thin shell that
/// calls into these and then re-arms the live program.
///
/// A playlist's list reads top→bottom as first→last, so `order` runs forward
/// (top = 0) — the opposite of the front-first Layers panel.
enum PlaylistEditing {

    /// The order value a newly appended entry should take: one past the current
    /// maximum (so the first entry in an empty playlist is 0).
    static func nextOrder(in entries: [PlaylistEntry]) -> Int {
        (entries.map(\.order).max() ?? -1) + 1
    }

    /// Builds an entry linking `item` to `playlist` at the next free order and
    /// appends it to the playlist's `entries`. The caller is responsible for
    /// inserting the returned entry into the `ModelContext`.
    @discardableResult
    static func makeEntry(for item: Item, in playlist: Playlist) -> PlaylistEntry {
        let entry = PlaylistEntry(order: nextOrder(in: playlist.entries))
        entry.item = item
        entry.playlist = playlist
        playlist.entries.append(entry)
        return entry
    }

    /// Applies a SwiftUI list move to entries shown in running order and rewrites
    /// each entry's `order` so it stays gapless `0..<n`, top = first.
    static func reorder(_ ordered: [PlaylistEntry],
                        from source: IndexSet, to destination: Int) {
        var arr = ordered
        arr.move(fromOffsets: source, toOffset: destination)
        for (index, entry) in arr.enumerated() {
            entry.order = index
        }
    }

    /// Drops `entry` from its playlist and renumbers the remaining entries so
    /// `order` stays gapless. The caller is responsible for deleting the removed
    /// entry from the `ModelContext`.
    static func remove(_ entry: PlaylistEntry, from playlist: Playlist) {
        playlist.entries.removeAll { $0 === entry }
        for (index, remaining) in playlist.orderedEntries.enumerated() {
            remaining.order = index
        }
    }

    /// A default name for a new playlist that doesn't collide with existing ones —
    /// "Untitled Playlist", then "Untitled Playlist 2", 3, … if taken. Mirrors the
    /// "Untitled Song" default in ``OperatorView/newAuthoredItem``.
    static func defaultPlaylistName(existing: [Playlist]) -> String {
        let base = "Untitled Playlist"
        let taken = Set(existing.map(\.name))
        guard taken.contains(base) else { return base }
        var n = 2
        while taken.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }
}
