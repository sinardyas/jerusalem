# `PlaylistContentPane.swift`

> The right half of the sidebar's Playlists split: rename the selected playlist and add / reorder / remove its items.

**Location:** `Sources/Jerusalem/Views/PlaylistContentPane.swift`
**Role:** SwiftUI view — sidebar sub-pane (playlist contents editor)

## What it does (plain English)

When a playlist is selected in the sidebar, this pane shows its items: a name field at the top, then a reorderable list of entries (each is a Library item with the item's icon, title, and a trash button). You add items by **dragging them from the Library** and dropping anywhere in the pane, reorder by dragging rows, and remove with the trash button or the **Delete** key. If no playlist is selected, it shows a friendly placeholder.

The file is split into a thin public wrapper (`PlaylistContentPane`, which takes an *optional* playlist) and a private inner editor (`PlaylistContentEditor`) that works with a *non-optional* playlist so it can use `@Bindable` for the name field. The actual ordering math lives elsewhere (`PlaylistEditing`); after every edit it calls back to re-arm the live program.

## Swift you'll meet in this file

- **`let playlist: Playlist?`** — `Playlist?` is "a Playlist or null". The wrapper accepts nothing-selected.
- **`var onChange: () -> Void` / `var onAddItems: ([String], Playlist) -> Void`** — callback props (closures). `([String], Playlist) -> Void` takes the dragged uuid strings plus the target playlist.
- **`if let playlist { ... } else { ContentUnavailableView(...) }`** — optional binding; `ContentUnavailableView` is the system "empty state" placeholder (icon + title + description).
- **`.id(playlist.persistentModelID)`** — forcing a fresh view identity when the id changes (like a React `key`), so row selection resets when you switch playlists.
- **`@Bindable var playlist: Playlist`** — makes `$playlist.name` a two-way binding into the model.
- **`@State private var selection` / `@State private var isDropTarget`** — `useState` for the selected row and the drag-highlight flag.
- **`List(selection: $selection) { ForEach(...) { ... }.onMove { ... } }`** — a list with drag-to-reorder; `.onMove(source, destination)` fires on a reorder.
- **`.dropDestination(for: String.self) { ids, _ in ...; return true } isTargeted: { isDropTarget = $0 }`** — a drop zone; the `isTargeted` closure toggles the highlight.
- **`.onDeleteCommand(perform:)`** — binds the Delete key.
- **`Button(role: .destructive, action:)`** — a destructive button (red styling); `role` is a semantic hint.
- **`Spacer(minLength:)`** — a flex spacer pushing the trash button to the right.

## Code walkthrough

### The wrapper: optional → placeholder or editor

```swift
struct PlaylistContentPane: View {
    let playlist: Playlist?
    var onChange: () -> Void
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
```

The `.id(...)` is the key detail: when you switch from one playlist to another, the identity changes, SwiftUI rebuilds the inner editor, and the row `selection` `@State` resets — no stale selection carried across playlists.

### The inner editor's `body`

```swift
var body: some View {
    VStack(spacing: 0) {
        header
        Divider()
        if playlist.entries.isEmpty {
            ContentUnavailableView("No Items", systemImage: "tray",
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
    .overlay { if isDropTarget { /* accent border */ } }
    .dropDestination(for: String.self) { ids, _ in
        onAddItems(ids, playlist)
        return true
    } isTargeted: { isDropTarget = $0 }
}
```

A vertical stack: the `header` (name field + count), a divider, then either an empty-state placeholder or a reorderable `List`. `playlist.orderedEntries` is the playlist's items in running order. `.onMove` delegates the actual index math to `PlaylistEditing.reorder(...)` and then calls `onChange()` to re-arm.

The whole pane is a drop target (not the individual rows — the comment notes this avoids fighting the drag-to-reorder). When something is dragged over it, `isTargeted` flips `isDropTarget`, which draws an accent-colored border overlay. On drop, `onAddItems(ids, playlist)` adds the dragged Library items.

### The header (rename in place)

```swift
private var header: some View {
    VStack(alignment: .leading, spacing: 4) {
        TextField("Playlist name", text: $playlist.name)
            .textFieldStyle(.plain)
            .font(.headline)
        Text("\(playlist.entries.count) item\(playlist.entries.count == 1 ? "" : "s")")
            .font(.caption).foregroundStyle(.secondary)
    }
    ...
}
```

`$playlist.name` binds straight to the model (autosaved), and a caption shows the pluralized item count.

### Removing entries

```swift
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
```

`removeEntry` detaches the entry via `PlaylistEditing.remove`, deletes the join row from the `modelContext`, and re-arms via `onChange()`. `deleteSelected` (bound to the Delete key) resolves the selected id to its `PlaylistEntry` first; `guard let ... else { return }` bails if nothing matches.

### `PlaylistEntryRow`

```swift
private struct PlaylistEntryRow: View {
    let entry: PlaylistEntry
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: entry.item?.kind.symbolName ?? "questionmark.square.dashed")
                ...
            Text(entry.item?.title ?? "Missing item")
                ...
            Spacer(minLength: 4)
            Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                .buttonStyle(.borderless)
        }
    }
}
```

One row: the item's kind glyph, its title, a flex spacer, and a trash button. The `entry.item?` optional chaining handles a *missing* item gracefully — it falls back to a dashed question-mark icon and "Missing item" text (greyed out via `.secondary`) instead of crashing.

## How it connects

- Receives `playlist: Playlist?` from `SidebarView` (the resolved `selectedPlaylist`) plus `onChange` and `onAddItems` callbacks that ultimately re-arm `LiveState` in `OperatorView`.
- Reads/writes the SwiftData models directly: `$playlist.name`, `playlist.orderedEntries`, and `modelContext.delete(...)`.
- Delegates pure order logic to the `PlaylistEditing` namespace (`reorder`, `remove`) — the view stays thin, matching the project convention of pushing decidable rules into testable caseless enums.
- Drop targets accept the uuids that `SidebarView` rows make `.draggable`.

## Gotchas / why it matters

- **Optional wrapper + non-optional inner view** is a common SwiftUI pattern: `@Bindable` needs a concrete model, so the optional is unwrapped once at the boundary.
- **`.id(playlist.persistentModelID)`** prevents the dangerous bug where a row index selected in playlist A still points at something in playlist B after switching — switching resets selection.
- **Drop target on the container, not the rows** — deliberately, so adding-by-drop doesn't conflict with reorder-by-drag.
- **Missing items don't crash** — `entry.item?` everywhere means a deleted/orphaned item shows a placeholder, supporting the "never fail on Sunday" promise.
- **Every mutation calls `onChange()`** so the live program re-arms, but (per the value-snapshot rule) the audience screen only changes when the operator explicitly acts.
