import SwiftUI
import SwiftData

/// The source-list sidebar: playlists at the top, the (search-filtered) library
/// below. Selecting a playlist or item arms it as the live program.
struct SidebarView: View {
    let items: [Item]
    let playlists: [Playlist]
    @Binding var selection: PersistentIdentifier?

    var body: some View {
        List(selection: $selection) {
            Section("Playlists") {
                if playlists.isEmpty {
                    Text("No playlists yet")
                        .foregroundStyle(.secondary).font(.callout)
                } else {
                    ForEach(playlists) { playlist in
                        Label(playlist.name, systemImage: "music.note.list")
                            .badge(playlist.entries.count)
                            .tag(playlist.persistentModelID)
                    }
                }
            }

            Section("Library") {
                if items.isEmpty {
                    Text("No matching items")
                        .foregroundStyle(.secondary).font(.callout)
                } else {
                    ForEach(items) { item in
                        Label(item.title, systemImage: item.kind.symbolName)
                            .tag(item.persistentModelID)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Jerusalem")
    }
}

#Preview {
    SidebarView(items: [], playlists: [], selection: .constant(nil))
}
