# `SidebarView.swift`

> The operator window's source list: a search-filtered Library on top, and a Playlists area below (names on the left, the selected playlist's items on the right).

**Location:** `Sources/Jerusalem/Views/SidebarView.swift`
**Role:** SwiftUI view — the operator window's sidebar (navigation / library / playlists)

## What it does (plain English)

This is the leftmost column of the operator window. The top half is the **Library** — every song/Bible/text/media item, filtered by the search box; clicking one selects it and shows its slides in the middle pane. The bottom half is the **Playlists** area, split again: a narrow list of playlist *names* on the left, and the contents of the selected playlist on the right (delegated to `PlaylistContentPane`).

The Library and the playlist-names list **share one selection binding**, so picking an item clears any playlist selection and vice versa — there's always exactly one thing selected. You can drag a Library item onto a playlist name to add it, and right-click a playlist to Rename or Delete it.

## Swift you'll meet in this file

- **`struct SidebarView: View { var body: some View }`** — SHAPE: value-type `struct` conforming to `View`, with a `body`. TS analog: `function SidebarView(): JSX.Element { return (...) }`; `some View` ≈ `: JSX.Element`.
- **`let libraryItems: [Item]` / `@Binding var selection: PersistentIdentifier?`** — props passed down from `OperatorView`. `@Binding` is a two-way prop (read + write); the parent owns the value, this view can change it. `PersistentIdentifier?` is a nullable SwiftData row id. TS analog: `selection: [value, setValue]` (state passed down).
- **`var onChange: () -> Void`** — a callback prop (a closure with no args, returns nothing); `() -> Void` ≈ `() => void`. Called after edits so the parent can re-arm the live program.
- **`VSplitView` / `HSplitView`** — AppKit-backed split containers with a **draggable divider** (vertical = stacked, horizontal = side-by-side). Different from `VStack`/`HStack`, which are fixed. TS analog: resizable split panes.
- **`List(selection: $selection) { Section("Library") { ForEach(...) { ... } } }`** — a sidebar-style table with a section header; `ForEach` is `.map`; `.tag(...)` marks each row's selection value. TS analog: `<List selection={...}><Section title="Library">...</Section></List>`.
- **`.draggable(item.uuid.uuidString)`** — makes a row draggable, carrying its uuid string as the payload. TS analog: `draggable` + `onDragStart` setting the payload.
- **`.dropDestination(for: String.self) { ids, _ in ... }`** — accepts dropped strings (the dragged uuids); the closure handles them and returns `true` if accepted. TS analog: `onDrop`.
- **`.contextMenu { Button("Rename") {...} }`** — the right-click menu. TS analog: a custom context menu.
- **`@Bindable var playlist: Playlist`** — promotes a model to bindable so `$playlist.name` is a two-way field binding. TS analog: model + setter.
- **`@FocusState private var focused: Bool`** — tracks/controls whether a field is focused (think a managed `isFocused` you can also *set*). TS analog: a focus ref/state you can read and assign.
- **`@State private var renamingID`** — `useState`; tracks which playlist row is in rename mode. TS analog: `const [renamingID, setRenamingID] = useState(...)`.

## Code walkthrough

### The two-level split layout

```swift
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
```

**TypeScript equivalent**

```tsx
function SidebarView(): JSX.Element {
  return (
    // analogy: VSplitView -> vertical resizable split (draggable divider)
    <VSplitView title="Jerusalem">
      <div style={{ minHeight: 120 }}>{libraryList}</div>
      {/* analogy: HSplitView -> horizontal resizable split */}
      <HSplitView style={{ minHeight: 180 }}>
        <div style={{ minWidth: 130, maxWidth: 220 }}>{playlistNamesList}</div>
        <div style={{ minWidth: 190 }}>
          <PlaylistContentPane
            playlist={selectedPlaylist}
            onChange={onChange}
            onAddItems={onAddItems}
          />
        </div>
      </HSplitView>
    </VSplitView>
  );
}
```

**Swift syntax:**
- `VSplitView { ... }` / `HSplitView { ... }` — trailing-closure containers with a *draggable* divider (unlike the fixed `VStack`/`HStack`). TS analog: resizable split-pane components.
- `.frame(minHeight: 120, idealHeight: 240)` — size constraints on a child. TS analog: CSS `min-height`/`height` hints.

A vertical split: `libraryList` on top, and below it a horizontal split of `playlistNamesList` (left) and `PlaylistContentPane` (right). `selectedPlaylist` is computed by matching the shared `selection` id against `playlists`, so the right pane follows whichever playlist name is selected.

### The Library list

```swift
private var libraryList: some View {
    List(selection: $selection) {
        Section("Library") {
            if libraryItems.isEmpty {
                Text("No matching items").foregroundStyle(.secondary).font(.callout)
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
```

**TypeScript equivalent**

```tsx
const libraryList = (
  <List className="sidebar" selection={[selection, setSelection]}>
    <Section title="Library">
      {libraryItems.length === 0 ? (
        <Text className="secondary callout">No matching items</Text>
      ) : (
        libraryItems.map(item => (
          <Label
            key={item.persistentModelID}
            value={item.persistentModelID}            // .tag(...) -> selection value
            icon={item.kind.symbolName}
            text={item.title}
            // analogy: .draggable(payload) -> draggable + onDragStart setting the payload
            draggable
            onDragStart={e => e.dataTransfer.setData("text", item.uuid.toString())}
          />
        ))
      )}
    </Section>
  </List>
);
```

**Swift syntax:**
- `List(selection: $selection) { ... }` — a list whose selection is two-way bound to `$selection`; clicking a row writes its `.tag(...)` into it. TS analog: a controlled list with `selection`/`onChange`.
- `Label(item.title, systemImage: item.kind.symbolName)` — a row of icon + text. TS analog: `<Label icon=... text=... />`.
- `.tag(item.persistentModelID)` — the value written to the selection when this row is picked. TS analog: a `value`/`key` per row.
- `.draggable(item.uuid.uuidString)` — make the row draggable with the uuid string as payload. TS analog: `draggable` + `onDragStart`.

Each row is a `Label` (icon + title). `.tag(item.persistentModelID)` is what gets written into `$selection` when the row is clicked. `.draggable(item.uuid.uuidString)` lets you drag the item onto a playlist. The empty branch shows "No matching items" (because the list is already search-filtered upstream).

### The playlist-names list

Mirrors the Library list but over `playlists`, rendering each as a `PlaylistNameRow`. Both lists bind to the *same* `$selection`, which is exactly why selecting one clears the other.

```swift
private var playlistNamesList: some View {
    List(selection: $selection) {
        Section("Playlists") {
            if playlists.isEmpty {
                Text("No playlists yet").foregroundStyle(.secondary).font(.callout)
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
```

**TypeScript equivalent**

```tsx
const playlistNamesList = (
  <List className="sidebar" selection={[selection, setSelection]}>
    <Section title="Playlists">
      {playlists.length === 0 ? (
        <Text className="secondary callout">No playlists yet</Text>
      ) : (
        playlists.map(playlist => (
          <PlaylistNameRow
            key={playlist.persistentModelID}
            playlist={playlist}
            renamingID={[renamingID, setRenamingID]}    // $renamingID -> two-way prop
            onDelete={() => onDeletePlaylist(playlist)}
            onAddItems={onAddItems}
          />
        ))
      )}
    </Section>
  </List>
);
```

**Swift syntax:**
- `renamingID: $renamingID` — passing a `@State` as a `@Binding` (two-way) down to the child. TS analog: passing `[value, setValue]`.
- `onDelete: { onDeletePlaylist(playlist) }` — a closure that captures `playlist`. TS analog: `() => onDeletePlaylist(playlist)`.

### `PlaylistNameRow` — name, badge, rename, drop, delete

```swift
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
```

**TypeScript equivalent**

```tsx
function PlaylistNameRow({
  playlist,
  renamingID: [renamingID, setRenamingID],
  onDelete,
  onAddItems,
}: {
  playlist: Playlist;
  renamingID: [PersistentIdentifier | null, (v: PersistentIdentifier | null) => void];
  onDelete: () => void;
  onAddItems: (ids: string[], pl: Playlist) => void;
}): JSX.Element {
  const inputRef = useRef<HTMLInputElement>(null);  // @FocusState
  const isRenaming = renamingID === playlist.persistentModelID;

  return (
    // analogy: Group { } -> a transparent wrapper (Fragment) that still takes modifiers
    <div
      data-value={playlist.persistentModelID}                     // .tag(...)
      onDrop={e => { onAddItems(readIds(e), playlist); }}          // .dropDestination
      onContextMenu={openMenu([                                   // .contextMenu
        { label: "Rename", onClick: () => setRenamingID(playlist.persistentModelID) },
        { label: "Delete Playlist", destructive: true, onClick: onDelete },
      ])}
    >
      {isRenaming ? (
        <input
          ref={inputRef}
          className="roundedBorder"
          value={playlist.name}
          onChange={e => (playlist.name = e.target.value)}
          autoFocus                                   // .onAppear { focused = true }
          onKeyDown={e => { if (e.key === "Enter") setRenamingID(null); }}  // .onSubmit
          onBlur={() => setRenamingID(null)}          // focus loss ends editing
        />
      ) : (
        <Label icon="music.note.list" text={playlist.name} badge={playlist.entries.length} />
      )}
    </div>
  );
}
```

**Swift syntax:**
- `Group { if isRenaming { ... } else { ... } }` — `Group` is a transparent container that can still take modifiers (`.tag`, `.dropDestination`, `.contextMenu`) applied to *both* branches. TS analog: a `Fragment`/wrapper holding shared props.
- `@FocusState private var focused: Bool` + `.focused($focused)` — a two-way focus binding: read it to know focus, set it to *move* focus. TS analog: a focus ref plus `autoFocus`/`.focus()`.
- `.onAppear { focused = true }` — auto-focus on mount. TS analog: `autoFocus` / `useEffect(() => ref.current?.focus(), [])`.
- `.onSubmit { ... }` — fires on Enter; `.onExitCommand { ... }` fires on Esc. TS analog: `onKeyDown` checking `Enter`/`Escape`.
- `.onChange(of: focused) { _, isFocused in if !isFocused { ... } }` — react to focus loss. TS analog: `onBlur`.
- `.badge(playlist.entries.count)` — a trailing count badge on the row. TS analog: a `badge` prop.

The row swaps between two shapes based on `isRenaming`:

- **Normal:** a `Label` with the playlist name and a `.badge(...)` showing the entry count.
- **Renaming:** a focused `TextField` bound to `$playlist.name`. `.onAppear { focused = true }` auto-focuses it; **Enter** (`.onSubmit`), **Esc** (`.onExitCommand`), or **clicking away** (`.onChange(of: focused)`) all end editing by clearing `renamingID`. Because the field binds straight to the model and SwiftData autosaves, the rename persists with no explicit save.

`.dropDestination` lets you drop dragged Library uuids onto this row (calls `onAddItems`). `.contextMenu` provides Rename (enters edit mode) and a destructive Delete.

## How it connects

- **Props from `OperatorView`:** `libraryItems` (already search-filtered there), `playlists`, the shared `$selection`, and three callbacks — `onChange` (re-arm after edits), `onDeletePlaylist`, and `onAddItems` (the drop handler that appends dragged items).
- **Delegates** the playlist contents to `PlaylistContentPane`, passing the resolved `selectedPlaylist` and the same `onChange`/`onAddItems`.
- Drag-and-drop ties the Library and Playlists together: rows are `.draggable` by uuid, and both `PlaylistNameRow` and the content pane accept those uuids as drops.
- Selection drives the operator's detail pane — pick a Library item to see its slide grid, pick a playlist to see its grouped slides.

## Gotchas / why it matters

- **Single shared `$selection`** is intentional: it guarantees exactly one of (library item, playlist) is active, so the detail pane and inspector always have an unambiguous subject.
- **Rename ends three ways** — Enter, Esc, and focus-loss all commit/exit. Relying on autosave means there's no separate "save" step, which keeps the live operator flow simple.
- **Drop target lives on the name row**, so dragging into a playlist works even before opening it. The matching content-pane drop target covers the empty state.
- **`onChange` re-arms the program** — any edit here can affect what's queued live, so the parent re-arms `LiveState` afterward (without changing the audience output until the operator acts).
