# `PlaylistContentPane.swift`

> The right half of the sidebar's Playlists split: rename the selected playlist and add / reorder / remove its items.

**Location:** `Sources/Jerusalem/Views/PlaylistContentPane.swift`
**Role:** SwiftUI view — sidebar sub-pane (playlist contents editor)

## What it does (plain English)

When a playlist is selected in the sidebar, this pane shows its items: a name field at the top, then a reorderable list of entries (each is a Library item with the item's icon, title, and a trash button). You add items by **dragging them from the Library** and dropping anywhere in the pane, reorder by dragging rows, and remove with the trash button or the **Delete** key. If no playlist is selected, it shows a friendly placeholder.

The file is split into a thin public wrapper (`PlaylistContentPane`, which takes an *optional* playlist) and a private inner editor (`PlaylistContentEditor`) that works with a *non-optional* playlist so it can use `@Bindable` for the name field. The actual ordering math lives elsewhere (`PlaylistEditing`); after every edit it calls back to re-arm the live program.

## Swift you'll meet in this file

- **`struct PlaylistContentPane: View { var body: some View }`** — SHAPE: value-type `struct` conforming to `View`, with a `body`. TS analog: `function PlaylistContentPane(): JSX.Element { return (...) }`; `some View` ≈ `: JSX.Element`.
- **`let playlist: Playlist?`** — `Playlist?` is "a Playlist or null". The wrapper accepts nothing-selected. TS analog: `playlist: Playlist | null`.
- **`var onChange: () -> Void` / `var onAddItems: ([String], Playlist) -> Void`** — callback props (closures). SHAPE: `(args) -> Void` ≈ `(args) => void`; `([String], Playlist)` takes the dragged uuid strings plus the target playlist. TS analog: `onAddItems: (ids: string[], pl: Playlist) => void`.
- **`if let playlist { ... } else { ContentUnavailableView(...) }`** — optional binding; `ContentUnavailableView` is the system "empty state" placeholder (icon + title + description). TS analog: `playlist ? <Editor/> : <EmptyState/>`.
- **`.id(playlist.persistentModelID)`** — forcing a fresh view identity when the id changes (like a React `key`), so row selection resets when you switch playlists.
- **`@Bindable var playlist: Playlist`** — makes `$playlist.name` a two-way binding into the model. TS analog: the model plus a setter.
- **`@State private var selection` / `@State private var isDropTarget`** — `useState` for the selected row and the drag-highlight flag. TS analog: `const [selection, setSelection] = useState(...)`.
- **`List(selection: $selection) { ForEach(...) { ... }.onMove { ... } }`** — a list with drag-to-reorder; `.onMove(source, destination)` fires on a reorder. TS analog: `<List>` with `onMove`.
- **`.dropDestination(for: String.self) { ids, _ in ...; return true } isTargeted: { isDropTarget = $0 }`** — a drop zone; the `isTargeted` closure toggles the highlight. TS analog: `onDrop` + `onDragOver`.
- **`.onDeleteCommand(perform:)`** — binds the Delete key. TS analog: a `keydown`/`Delete` handler.
- **`Button(role: .destructive, action:)`** — a destructive button (red styling); `role` is a semantic hint. TS analog: `<button className="destructive" onClick={...}>`.
- **`Spacer(minLength:)`** — a flex spacer pushing the trash button to the right. TS analog: `<div style={{ flex: 1 }} />`.

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

**TypeScript equivalent**

```tsx
function PlaylistContentPane({
  playlist,
  onChange,
  onAddItems,
}: {
  playlist: Playlist | null;
  onChange: () => void;
  onAddItems: (ids: string[], pl: Playlist) => void;
}): JSX.Element {
  if (playlist) {
    return (
      <PlaylistContentEditor
        // analogy: .id(...) -> React key; new key remounts and resets local state
        key={playlist.persistentModelID}
        playlist={playlist}
        onChange={onChange}
        onAddItems={onAddItems}
      />
    );
  } else {
    return (
      <EmptyState
        title="No Playlist Selected"
        icon="music.note.list"
        description="Select a playlist on the left to edit its items."
      />
    );
  }
}
```

**Swift syntax:**
- `if let playlist { ... } else { ... }` — shorthand optional binding (reuses the name); the non-null `playlist` is in scope inside the first branch. TS analog: `if (playlist) { ... } else { ... }`.
- `.id(playlist.persistentModelID)` — sets a stable identity; changing it makes SwiftUI rebuild the subtree and reset its `@State`. TS analog: the `key` prop.

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

**TypeScript equivalent**

```tsx
function PlaylistContentEditor(): JSX.Element {
  return (
    // analogy: VStack -> vertical column
    <div
      className="column"
      // analogy: .dropDestination + isTargeted -> onDrop + onDragOver/onDragLeave
      onDragOver={() => setIsDropTarget(true)}
      onDragLeave={() => setIsDropTarget(false)}
      onDrop={e => { onAddItems(readIds(e), playlist); setIsDropTarget(false); }}
    >
      {header}
      <Divider />

      {playlist.entries.length === 0 ? (
        <EmptyState title="No Items" icon="tray" description="Drag items here from the Library." />
      ) : (
        <List
          className="inset"
          selection={[selection, setSelection]}
          onDelete={deleteSelected}                 // .onDeleteCommand -> Delete key
        >
          {playlist.orderedEntries.map(entry => (
            <PlaylistEntryRow
              key={entry.persistentModelID}
              entry={entry}
              onDelete={() => removeEntry(entry)}
            />
          ))}
          {/* analogy: .onMove(source, destination) -> reorder handler */}
          <OnMove handler={(source, destination) => {
            PlaylistEditing.reorder(playlist.orderedEntries, source, destination);
            onChange();
          }} />
        </List>
      )}

      {isDropTarget && <div className="accentBorderOverlay" />}
    </div>
  );
}
```

**Swift syntax:**
- `ForEach(playlist.orderedEntries, id: \.persistentModelID) { entry in ... }` — `ForEach(_, id:)` needs a stable identity per row; `\.persistentModelID` is a key path (`e => e.persistentModelID`). TS analog: `.map(entry => <Row key={entry.persistentModelID} ... />)`.
- `.tag(entry.persistentModelID as PersistentIdentifier?)` — marks each row's selection value; `as PersistentIdentifier?` casts to the optional type the `List` selection expects. TS analog: a `value`/`key` on each row.
- `.onMove { source, destination in ... }` — trailing closure with named params for the reorder source/destination index sets. TS analog: `(source, destination) => ...`.
- `.dropDestination(for: String.self) { ids, _ in ...; return true } isTargeted: { isDropTarget = $0 }` — a drop zone declaring the accepted type (`String.self`); the first closure handles the drop (return `true` = accepted), `isTargeted:` toggles the hover flag (`$0` = is-hovering bool). TS analog: `onDrop` + `onDragOver`/`onDragLeave`.

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

**TypeScript equivalent**

```tsx
const header = (
  <div className="column" style={{ alignItems: "flex-start", gap: 4 }}>
    {/* $playlist.name -> two-way binding straight into the model */}
    <input
      placeholder="Playlist name"
      className="plain headline"
      value={playlist.name}
      onChange={e => (playlist.name = e.target.value)}
    />
    <Text className="caption secondary">
      {`${playlist.entries.length} item${playlist.entries.length === 1 ? "" : "s"}`}
    </Text>
  </div>
);
```

**Swift syntax:**
- `"\(playlist.entries.count) item\(playlist.entries.count == 1 ? "" : "s")"` — string interpolation with an inline ternary for pluralization. TS analog: `` `${n} item${n === 1 ? "" : "s"}` ``.

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

**TypeScript equivalent**

```ts
function removeEntry(entry: PlaylistEntry): void {
  PlaylistEditing.remove(entry, playlist);
  modelContext.delete(entry);
  onChange();
}

function deleteSelected(): void {
  // guard let ... else { return }: bail if nothing matches
  if (selection == null) return;
  const entry = playlist.entries.find(e => e.persistentModelID === selection);
  if (!entry) return;
  removeEntry(entry);
}
```

**Swift syntax:**
- `guard let selection, let entry = ... else { return }` — chained optional bindings in one `guard`; if any is `nil`, run `else` and return. TS analog: sequential `if (x == null) return;` checks.
- `playlist.entries.first(where: { $0.persistentModelID == selection })` — `.first(where:)` returns the first match or `nil`; `$0` is each entry. TS analog: `.find(e => ...)`.

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

**TypeScript equivalent**

```tsx
function PlaylistEntryRow({
  entry,
  onDelete,
}: {
  entry: PlaylistEntry;
  onDelete: () => void;
}): JSX.Element {
  return (
    // analogy: HStack -> horizontal row
    <div className="row" style={{ gap: 8 }}>
      {/* entry.item?.… ?? fallback handles a deleted/orphaned item without crashing */}
      <Icon name={entry.item?.kind.symbolName ?? "questionmark.square.dashed"} />
      <Text className={entry.item == null ? "secondary" : "primary"}>
        {entry.item?.title ?? "Missing item"}
      </Text>
      <div style={{ flex: 1 }} />  {/* Spacer(minLength: 4) */}
      <button className="destructive borderless" onClick={onDelete} title="Remove from playlist">
        <Icon name="trash" />
      </button>
    </div>
  );
}
```

**Swift syntax:**
- `entry.item?.kind.symbolName ?? "..."` — optional chaining (`?.`) then `??` fallback: if `entry.item` is `nil`, the whole chain is `nil` and the fallback kicks in. TS analog: `entry.item?.kind.symbolName ?? "..."`.
- `Button(role: .destructive, action: onDelete) { ... }` — passing the action as a named arg and the label as the trailing closure. TS analog: `<button onClick={onDelete}>...</button>`.

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
