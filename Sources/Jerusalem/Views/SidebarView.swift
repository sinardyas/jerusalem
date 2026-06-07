import SwiftUI
import SwiftData

/// The source list. Top: the (search-filtered) Library — selecting an item shows its
/// slides in the detail pane. Below a draggable divider: the Playlists area, itself
/// split left/right — playlist **names** on the left, the selected playlist's
/// **items** on the right (``PlaylistContentPane``), where add/remove/reorder happen.
/// Library and playlist-name lists share `$selection` so picking one clears the
/// other; `onChange` re-arms the live program after an edit.
struct SidebarView: View {
    let libraryItems: [Item]    // search-filtered, for the Library list
    let playlists: [Playlist]
    @Binding var selection: PersistentIdentifier?
    var onChange: () -> Void
    var onDeletePlaylist: (Playlist) -> Void
    /// Adds dragged Library item uuids to a playlist (drop handler).
    var onAddItems: ([String], Playlist) -> Void

    /// The playlist whose name row is being edited in place (right-click → Rename).
    @State private var renamingID: PersistentIdentifier?

    private var selectedPlaylist: Playlist? {
        playlists.first { $0.persistentModelID == selection }
    }

    var body: some View {
        VSplitView {
            libraryList
                .frame(minHeight: 120, idealHeight: 240)
            HSplitView {
                playlistNamesList
                    .frame(minWidth: 130, idealWidth: 150, maxWidth: 220)
                PlaylistContentPane(playlist: selectedPlaylist, onChange: onChange,
                                    onAddItems: onAddItems)
                    .frame(minWidth: 190)
            }
            .frame(minHeight: 180, idealHeight: 280)
        }
        .navigationTitle("Jerusalem")
    }

    private var libraryList: some View {
        List(selection: $selection) {
            Section("Library") {
                if libraryItems.isEmpty {
                    Text("No matching items")
                        .foregroundStyle(.secondary).font(.callout)
                } else {
                    ForEach(libraryItems) { item in
                        Label(item.title, systemImage: item.kind.symbolName)
                            .tag(item.persistentModelID)
                            .draggable(item.uuid.uuidString)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var playlistNamesList: some View {
        List(selection: $selection) {
            Section("Playlists") {
                if playlists.isEmpty {
                    Text("No playlists yet")
                        .foregroundStyle(.secondary).font(.callout)
                } else {
                    ForEach(playlists) { playlist in
                        PlaylistNameRow(playlist: playlist,
                                        renamingID: $renamingID,
                                        onDelete: { onDeletePlaylist(playlist) },
                                        onAddItems: onAddItems)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

/// One playlist row: shows the name + entry-count badge, accepts dragged Library items
/// as a drop target, and offers Rename / Delete via right-click. Choosing Rename swaps
/// the label for a focused text field bound to `playlist.name`; Enter or click-away
/// commits (autosaved), Esc ends editing.
private struct PlaylistNameRow: View {
    @Bindable var playlist: Playlist
    @Binding var renamingID: PersistentIdentifier?
    var onDelete: () -> Void
    var onAddItems: ([String], Playlist) -> Void

    @FocusState private var focused: Bool

    private var isRenaming: Bool { renamingID == playlist.persistentModelID }

    var body: some View {
        Group {
            if isRenaming {
                TextField("Playlist name", text: $playlist.name)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onAppear { focused = true }
                    .onSubmit { renamingID = nil }
                    .onExitCommand { renamingID = nil }
                    .onChange(of: focused) { _, isFocused in
                        if !isFocused { renamingID = nil }
                    }
            } else {
                Label(playlist.name, systemImage: "music.note.list")
                    .badge(playlist.entries.count)
            }
        }
        .tag(playlist.persistentModelID)
        .dropDestination(for: String.self) { ids, _ in
            onAddItems(ids, playlist)
            return true
        }
        .contextMenu {
            Button("Rename") { renamingID = playlist.persistentModelID }
            Button("Delete Playlist", role: .destructive) { onDelete() }
        }
    }
}

#Preview {
    SidebarView(libraryItems: [], playlists: [],
                selection: .constant(nil),
                onChange: {}, onDeletePlaylist: { _ in },
                onAddItems: { _, _ in })
}
