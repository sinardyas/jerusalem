import SwiftUI
import SwiftData

/// The right pane of the sidebar's Playlists split: the selected playlist's items.
/// Rename it, drag items in from the Library to add, drag to reorder, and trash /
/// Delete to remove. Pure order math lives in ``PlaylistEditing``; `onChange` re-arms
/// the live program after every edit. Shows a placeholder until a playlist is
/// selected on the left.
struct PlaylistContentPane: View {
    let playlist: Playlist?
    var onChange: () -> Void
    /// Adds dragged Library item uuids to this playlist (drop handler).
    var onAddItems: ([String], Playlist) -> Void

    var body: some View {
        if let playlist {
            PlaylistContentEditor(playlist: playlist, onChange: onChange, onAddItems: onAddItems)
                .id(playlist.persistentModelID)   // reset row selection when switching playlists
        } else {
            ContentUnavailableView("No Playlist Selected",
                                   systemImage: "music.note.list",
                                   description: Text("Select a playlist on the left to edit its items."))
        }
    }
}

/// Editor for one (non-optional) playlist, so `@Bindable` can drive the name field.
private struct PlaylistContentEditor: View {
    @Bindable var playlist: Playlist
    var onChange: () -> Void
    var onAddItems: ([String], Playlist) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var selection: PersistentIdentifier?
    @State private var isDropTarget = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if playlist.entries.isEmpty {
                ContentUnavailableView("No Items",
                                       systemImage: "tray",
                                       description: Text("Drag items here from the Library."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selection) {
                    ForEach(playlist.orderedEntries, id: \.persistentModelID) { entry in
                        PlaylistEntryRow(entry: entry) { removeEntry(entry) }
                            .tag(entry.persistentModelID as PersistentIdentifier?)
                    }
                    .onMove { source, destination in
                        PlaylistEditing.reorder(playlist.orderedEntries, from: source, to: destination)
                        onChange()
                    }
                }
                .listStyle(.inset)
                .onDeleteCommand(perform: deleteSelected)
            }
        }
        // Drop anywhere in the pane (works in the empty state too). Lives on the outer
        // container, not the rows, so it doesn't fight the entries' drag-to-reorder.
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .padding(2)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: String.self) { ids, _ in
            onAddItems(ids, playlist)
            return true
        } isTargeted: { isDropTarget = $0 }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Playlist name", text: $playlist.name)
                .textFieldStyle(.plain)
                .font(.headline)
            Text("\(playlist.entries.count) item\(playlist.entries.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func removeEntry(_ entry: PlaylistEntry) {
        PlaylistEditing.remove(entry, from: playlist)
        modelContext.delete(entry)
        onChange()
    }

    private func deleteSelected() {
        guard let selection,
              let entry = playlist.entries.first(where: { $0.persistentModelID == selection })
        else { return }
        removeEntry(entry)
    }
}

/// One row in the playlist: the item's kind glyph, its title, and a trash button.
private struct PlaylistEntryRow: View {
    let entry: PlaylistEntry
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: entry.item?.kind.symbolName ?? "questionmark.square.dashed")
                .font(.callout)
                .foregroundStyle(entry.item == nil ? .secondary : .primary)
                .frame(width: 20)
            Text(entry.item?.title ?? "Missing item")
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(entry.item == nil ? .secondary : .primary)
            Spacer(minLength: 4)
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove from playlist")
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
