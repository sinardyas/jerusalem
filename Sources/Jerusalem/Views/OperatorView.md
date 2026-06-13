# `OperatorView.swift`

> The top-level operator (live-control) window — the control surface used live on Sunday morning to drive what's on the audience screen.

**Location:** `Sources/Jerusalem/Views/OperatorView.swift`
**Role:** SwiftUI view — the operator window (the main window shell)

## What it does (plain English)

This is the **main window** the operator stares at during a service. On the left is the library/playlist sidebar, in the middle is a grid of slide thumbnails, and on the right is an inspector that mirrors what's live. The operator picks a song (or playlist), then drives the live program **from the keyboard**: arrow keys / space advance slides, and the letters **B / C / L** are panic buttons (Black / Clear / Logo) that instantly blank or override the audience screen.

Crucially, this window is **presentation/live-control only**. As of Phase 8.5 all *editing* (title, lyrics, slide design) moved to a separate slide-editor window. This file opens that editor window when asked, but never edits content inline. That separation is a safety feature: fiddling with content can't change what the congregation sees.

The window also handles the plumbing that keeps things fast and reliable: a debounced search box, a memoized search index so filtering doesn't re-scan every slide on each keystroke, render-ahead/prewarming of the *next* slide and video, and restoring the last selection on relaunch so reopening the app lands where the service left off.

## Swift you'll meet in this file

- **`struct OperatorView: View { var body: some View }`** — SHAPE: a SwiftUI view is a value-type `struct` with a `body` property. TS analog: a React function component; `body` is the returned JSX. `some View` ≈ `: JSX.Element` ("returns *some* concrete View, exact type hidden").
- **`@Query(sort: \Item.title) private var items: [Item]`** — a *live database query* (SwiftData). SHAPE: `\Item.title` is a key path (`item => item.title`). TS analog: a data hook `const items = useLiveQuery(...)` that auto-re-renders when rows change.
- **`@Environment(LiveState.self) private var live`** — React-Context-style dependency injection. TS analog: `const live = useContext(LiveStateContext)`. `@Environment(\.modelContext)` is the SwiftData write session (a DB session); `@Environment(\.openWindow)` is the system function for opening another window.
- **`@State private var showInspector = true`** — `useState`. Local mutable UI state that triggers re-render on change. TS analog: `const [showInspector, setShowInspector] = useState(true)`.
- **`$searchText`** — the `$` prefix turns a `@State` value into a two-way **Binding** (a read/write handle), like passing both `value` and `onChange` as one prop.
- **`Task<Void, Never>?`** — a handle to an async task (`T?` = "T or null"). Used to cancel an in-flight debounce. TS analog: a cancellable `Promise<void> | null`.
- **`NavigationSplitView { sidebar } detail: { ... }`** — SHAPE: a trailing-closure container with extra labeled closures = a multi-column app shell (sidebar + content/detail). TS analog: `<SplitView sidebar={...} detail={...} />`. `.inspector(...)` adds a trailing panel; `.toolbar { }` adds the window toolbar; `.searchable(...)` adds the system search field.
- **`if let selectedItem { ... } else { ... }`** — optional binding: runs the first branch only when the optional is non-null, binding the unwrapped value. TS analog: `if (selectedItem) { ... } else { ... }`.
- **`NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in ... }`** — AppKit. SHAPE: installs a window-local keydown listener. TS analog: `window.addEventListener('keydown', e => ...)`. Returning `nil` swallows the key; returning `event` lets it pass through.
- **`MainActor.assumeIsolated { }`** — "this callback already runs on the main thread, so treat it as main-thread-isolated." Lets the closure touch main-thread-only state without `await`. TS analog: `// already on main thread` (JS has one thread anyway).
- **`class WindowRef { weak var window: NSWindow? }`** — SHAPE: a `class` is a reference type (shared, like a JS object). `weak` avoids a retain cycle so it doesn't keep the window alive. TS analog: a plain object held by reference; `weak` ≈ a `WeakRef`.
- **`NSViewRepresentable`** — a bridge that wraps an AppKit `NSView` so it can live inside SwiftUI. TS analog: a wrapper component bridging a non-React DOM widget.

## Code walkthrough

### State and derived values

The view holds query results (`items`, `playlists`), injected singletons (`live`, `output`, `modelContext`, `openWindow`), and a cluster of `@State`: the search text, its debounced copy, a cancellable `searchTask`, a memoized `searchIndex`, the current `selectedID`, the armed `program`, the `keyMonitor` handle, and a `windowRef` identity holder.

Derived (computed) properties filter and resolve the selection:

```swift
private var filteredItems: [Item] {
    guard !debouncedQuery.isEmpty else { return items }
    return items.filter {
        let haystack = searchIndex[$0.persistentModelID] ?? $0.searchableText
        return LibrarySearch.matches(query: debouncedQuery, in: haystack)
    }
}
```

**TypeScript equivalent**

```ts
// analogy: computed property -> a getter / memoized derived value
get filteredItems(): Item[] {
  if (debouncedQuery === "") return items;       // guard ... else return
  return items.filter(item => {                  // $0 -> item
    const haystack = searchIndex[item.persistentModelID] ?? item.searchableText;
    return LibrarySearch.matches(debouncedQuery, haystack);
  });
}
```

**Swift syntax:**
- `private var filteredItems: [Item] { ... }` — a computed (read-only) property; re-runs each access. TS analog: a getter.
- `guard !debouncedQuery.isEmpty else { return items }` — early-exit guard: if the condition is false, run `else` and bail. TS analog: `if (debouncedQuery === "") return items;`.
- `items.filter { ... }` with `$0` — trailing-closure `.filter`; `$0` is the implicit first arg (the item). TS analog: `items.filter(item => ...)`.
- `searchIndex[$0.persistentModelID] ?? $0.searchableText` — dictionary lookup with a `??` fallback. TS analog: `searchIndex[id] ?? item.searchableText`.

`$0` is the first closure argument (the item). `??` is nullish-coalescing — fall back to a fresh `searchableText` if it's not in the memoized index. `selectedItem` / `selectedPlaylist` resolve the single `selectedID` against either list (only one will match).

### The `body` — the window layout

```swift
var body: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
        SidebarView(libraryItems: filteredItems, playlists: playlists,
                    selection: $selectedID,
                    onChange: rebuildProgram,
                    onDeletePlaylist: deletePlaylist,
                    onAddItems: addItems)
            .navigationSplitViewColumnWidth(min: 340, ideal: 420, max: 560)
    } detail: {
        detailPane
            .inspector(isPresented: $showInspector) {
                InspectorView(item: selectedItem)
                    .inspectorColumnWidth(min: 280, ideal: 320, max: 380)
            }
            .toolbar { toolbarContent }
    }
    .searchable(text: $searchText, placement: .sidebar, prompt: "Search titles & lyrics…")
```

**TypeScript equivalent**

```tsx
function OperatorView(): JSX.Element {
  return (
    // analogy: NavigationSplitView { sidebar } detail: { } -> 3-pane app shell
    <SplitView
      columnVisibility={[columnVisibility, setColumnVisibility]}
      sidebar={
        <SidebarView
          libraryItems={filteredItems}
          playlists={playlists}
          selection={[selectedID, setSelectedID]}   // $selectedID -> two-way prop
          onChange={rebuildProgram}
          onDeletePlaylist={deletePlaylist}
          onAddItems={addItems}
          style={{ minWidth: 340, idealWidth: 420, maxWidth: 560 }}
        />
      }
      detail={
        <div>
          {detailPane}
          {/* .inspector -> trailing panel */}
          <Inspector open={[showInspector, setShowInspector]}>
            <InspectorView item={selectedItem} style={{ minWidth: 280, maxWidth: 380 }} />
          </Inspector>
          {/* .toolbar -> window toolbar */}
          <Toolbar>{toolbarContent}</Toolbar>
        </div>
      }
    />
    /* .searchable -> a search field placed in the sidebar */
  );
}
```

**Swift syntax:**
- `NavigationSplitView(columnVisibility: $columnVisibility) { ... } detail: { ... }` — a container taking an init arg plus two trailing closures (the sidebar and the `detail:` content). TS analog: a component with `sidebar`/`detail` render props.
- `.navigationSplitViewColumnWidth(...)` / `.inspector(...)` / `.toolbar { ... }` / `.searchable(...)` — `.modifier` chaining: each returns a wrapped view. TS analog: nested wrappers / props.
- `onChange: rebuildProgram` — passing a function by reference (no parens). TS analog: `onChange={rebuildProgram}`.

Read this like nested JSX: a split view with the `SidebarView` on the left and `detailPane` in the middle, the `InspectorView` attached as a trailing panel, the toolbar attached, and a search field placed in the sidebar.

The chained `.onChange` / `.onReceive` / `.onAppear` / `.onDisappear` modifiers wire the lifecycle:

```swift
    .onChange(of: searchText) { _, query in scheduleSearch(query) }
    .onChange(of: items.count) { _, _ in rebuildSearchIndex() }
    .onReceive(NotificationCenter.default.publisher(for: .slideEditorDidClose)) { _ in
        rebuildProgram()
        rebuildSearchIndex()
    }
    .onChange(of: selectedID) { _, _ in
        rebuildProgram()
        persistSelection()
    }
    .onChange(of: live.liveSlideID) { _, _ in
        VideoPrewarmer.shared.prewarm(live.nextProgramSlide?.videoCue)
        if let next = live.nextProgramSlide?.renderable {
            SlidePrewarmer.shared.prewarm(next, pixelSize: output.activeOutputPixelSize)
        }
    }
    .onAppear {
        if selectedID == nil {
            selectedID = LastPosition.resolve(LastPosition.load(), in: modelContext)
        }
        rebuildProgram()
        rebuildSearchIndex()
        installKeyMonitor()
    }
    .onDisappear(perform: removeKeyMonitor)
    .background(WindowAccessor { windowRef.window = $0 })
}
```

**TypeScript equivalent**

```tsx
// analogy: each .onChange / .onReceive / .onAppear / .onDisappear -> a useEffect
useEffect(() => { scheduleSearch(searchText); }, [searchText]);
useEffect(() => { rebuildSearchIndex(); }, [items.length]);

// analogy: .onReceive(NotificationCenter…) -> subscribe to an event bus
useEffect(() => {
  const off = bus.on("slideEditorDidClose", () => {
    rebuildProgram();      // re-arm so grid + audience pick up edits
    rebuildSearchIndex();  // content edits land here too
  });
  return off;
}, []);

useEffect(() => { rebuildProgram(); persistSelection(); }, [selectedID]);

useEffect(() => {
  VideoPrewarmer.shared.prewarm(live.nextProgramSlide?.videoCue);
  const next = live.nextProgramSlide?.renderable;
  if (next) SlidePrewarmer.shared.prewarm(next, output.activeOutputPixelSize);
}, [live.liveSlideID]);

useEffect(() => {
  // .onAppear
  if (selectedID == null) {
    setSelectedID(LastPosition.resolve(LastPosition.load(), modelContext));
  }
  rebuildProgram();
  rebuildSearchIndex();
  installKeyMonitor();
  return removeKeyMonitor; // .onDisappear cleanup
}, []);

// .background(WindowAccessor { windowRef.window = $0 }) -> learn this view's host window
```

**Swift syntax:**
- `.onChange(of: searchText) { _, query in ... }` — the closure receives `(oldValue, newValue)`; `_` drops old, `query` is new. TS analog: `useEffect(..., [searchText])`.
- `.onReceive(publisher) { _ in ... }` — subscribe to a Combine publisher (here `NotificationCenter`); `_` ignores the payload. TS analog: `bus.on("event", () => ...)`.
- `.onDisappear(perform: removeKeyMonitor)` — pass a function as the handler. TS analog: the cleanup `return` of a `useEffect`.
- `.background(WindowAccessor { windowRef.window = $0 })` — places an invisible accessor view behind; `$0` is the resolved `NSWindow`. TS analog: a hidden ref-grabbing component.

- `.onChange(of: searchText)` → debounce the search.
- `.onChange(of: items.count)` → rebuild the memoized search index when items are added/removed.
- `.onReceive(...slideEditorDidClose)` → when the separate editor window closes, **re-arm the program and rebuild the search index** so the grid + audience output pick up edits.
- `.onChange(of: selectedID)` → re-arm the program and persist the selection.
- `.onChange(of: live.liveSlideID)` → prewarm the *next* video clip and render-ahead the *next* slide image at output resolution.
- `.onAppear` → restore the last selection, build the program/index, and **install the key monitor**.
- `.onDisappear` → remove the key monitor.
- `.background(WindowAccessor { windowRef.window = $0 })` → learn this view's hosting `NSWindow`.

### Arming the program (arm vs. go-live)

```swift
private func rebuildProgram() {
    if let selectedItem {
        program = LiveState.programSlides(for: selectedItem)
    } else if let selectedPlaylist {
        program = LiveState.programSlides(for: selectedPlaylist)
    } else {
        program = []
    }
    live.arm(program)
    VideoPrewarmer.shared.prewarm(live.nextProgramSlide?.videoCue)
}
```

**TypeScript equivalent**

```ts
function rebuildProgram(): void {
  if (selectedItem) {
    setProgram(LiveState.programSlides(selectedItem));
  } else if (selectedPlaylist) {
    setProgram(LiveState.programSlides(selectedPlaylist));
  } else {
    setProgram([]);
  }
  live.arm(program);
  VideoPrewarmer.shared.prewarm(live.nextProgramSlide?.videoCue);
}
```

**Swift syntax:**
- `if let selectedItem { ... }` (no `= ...`) — shorthand optional binding that reuses the same name (`if let selectedItem = selectedItem`). TS analog: `if (selectedItem) { ... }`.

`live.arm(program)` **loads** the slides into `LiveState` without changing what's on screen. Going live is a separate, deliberate act — clicking a thumbnail (`live.goLive(id:)`) or pressing space/arrows (`live.next()`).

### The key monitor (the heart of live control)

```swift
private func installKeyMonitor() {
    guard keyMonitor == nil else { return }
    let live = self.live
    let windowRef = self.windowRef
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
        MainActor.assumeIsolated {
            guard NSApp.keyWindow === windowRef.window else { return event }
            if NSApp.keyWindow?.firstResponder is NSText { return event }
            switch event.keyCode {
            case 49, 124, 125: live.next(); return nil          // space, →, ↓
            case 123, 126: live.previous(); return nil           // ←, ↑
            default: break
            }
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "b": live.setPanic(.black); return nil
            case "c": live.setPanic(.clear); return nil
            case "l": live.setPanic(.logo); return nil
            default: return event
            }
        }
    }
}
```

**TypeScript equivalent**

```ts
function installKeyMonitor(): void {
  if (keyMonitor != null) return;            // guard keyMonitor == nil else { return }
  const live = self.live;                    // capture for the closure
  const windowRef = self.windowRef;

  // analogy: NSEvent.addLocalMonitorForEvents(.keyDown) -> addEventListener('keydown')
  keyMonitor = (event: KeyboardEvent) => {
    // analogy: MainActor.assumeIsolated { } -> // already on main thread

    // Guard 1: only drive the program when the OPERATOR window is key/focused.
    // === is identity (same object); returning the event lets the key bubble.
    if (NSApp.keyWindow !== windowRef.window) return event;

    // Guard 2: a text field is focused (e.g. the search box) -> let typing through.
    if (NSApp.keyWindow?.firstResponder instanceof NSText) return event;

    switch (event.keyCode) {
      case 49: case 124: case 125: live.next(); return null;      // space, →, ↓
      case 123: case 126: live.previous(); return null;           // ←, ↑
      default: break;
    }

    switch (event.charactersIgnoringModifiers?.toLowerCase()) {
      case "b": live.setPanic("black"); return null;
      case "c": live.setPanic("clear"); return null;
      case "l": live.setPanic("logo"); return null;
      default: return event;  // unhandled key -> let it bubble
    }
  };
  window.addEventListener("keydown", keyMonitor);
}
```

This is the live-control wiring, and there are two guards that matter:

1. **`guard NSApp.keyWindow === windowRef.window else { return event }`** — only drive the program when the *operator window* is the key (focused) window. If an editor window is focused, the key passes through unchanged. Editing must never advance or blank the audience screen.
2. **`if NSApp.keyWindow?.firstResponder is NSText { return event }`** — if a text field (like the search box) is focused, let the key through so typing works. `is NSText` is a type check.

Returning `nil` **consumes** the key (it stops here); returning `event` **lets it bubble**. The first `switch` maps macOS key codes for space/arrows to next/previous; the second maps the letters `b`/`c`/`l` to the three panic states. `removeKeyMonitor()` (called from `.onDisappear`) tears it down with `NSEvent.removeMonitor`.

**Swift syntax:**
- `guard keyMonitor == nil else { return }` — bail if a monitor already exists (install once). TS analog: `if (keyMonitor != null) return;`.
- `let live = self.live` — capture the values into locals so the long-lived closure holds *them*, not `self`. TS analog: pulling fields into `const`s before a callback.
- `NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in ... }` — the AppKit keydown-monitor pattern; the trailing closure returns the event (bubble) or `nil` (consume). TS analog: `addEventListener('keydown', e => ...)` plus `preventDefault()`/`stopPropagation()` for the "consume" case.
- `MainActor.assumeIsolated { }` — asserts the closure already runs on the main thread, so it may touch main-actor state synchronously. TS analog: nothing — JS is single-threaded; treat as a no-op comment.
- `NSApp.keyWindow === windowRef.window` — `===` is **reference identity** (same object), not value equality (`==`). TS analog: `===` on objects.
- `NSApp.keyWindow?.firstResponder is NSText` — `?.` optional chaining + `is` runtime type check. TS analog: `?.` + `instanceof`.
- `switch event.keyCode { case 49, 124, 125: ...; default: break }` — multiple values share one `case`; `break` falls out (each Swift case auto-breaks — no fallthrough). TS analog: stacked `case` labels.
- `event.charactersIgnoringModifiers?.lowercased()` switched as a `String?` — switching an optional; `case "b":` matches the unwrapped value, `default:` covers `nil` and anything else. TS analog: `switch (str?.toLowerCase())`.
- `.black` / `.clear` / `.logo` — enum-case shorthand for `LiveState.Panic.black` etc. TS analog: union members `"black"` / `"clear"` / `"logo"`.

### The toolbar

`toolbarContent` (a `@ToolbarContentBuilder`) lays out:
- **Edit** button (leading) → `openEditor(for: selectedItem)`, disabled when nothing is selected. This is how you reach the slide-editor window.
- **Output** menu (status) → start output on a chosen `NSScreen`, or stop it; shows "No displays detected" when none exist.
- **Add** menu + **Inspector** toggle (primary action) → create a new Song/Bible/Text item, import media, or create a playlist.

```swift
@ToolbarContentBuilder
private var toolbarContent: some ToolbarContent {
    ToolbarItem(placement: .navigation) {
        Button { openEditor(for: selectedItem) } label: {
            Label("Edit", systemImage: "square.and.pencil")
        }
        .help("Edit this item — title, content, and slide design")
        .disabled(selectedItem == nil)
    }
    ToolbarItem(placement: .status) {
        Menu {
            if output.isActive {
                Button("Stop Output", systemImage: "stop.fill") { output.stop() }
                Divider()
            }
            if output.screens.isEmpty {
                Text("No displays detected")
            } else {
                ForEach(output.screens) { screen in
                    Button { output.start(screenID: screen.id) } label: {
                        Label(screen.name, systemImage: "display")
                    }
                }
            }
        } label: {
            Label(output.isActive ? output.activeScreenName : "Start Output",
                  systemImage: output.isActive ? "tv.fill" : "tv")
        }
    }
    ToolbarItemGroup(placement: .primaryAction) {
        Menu {
            Button("New Song", systemImage: "music.note") { newAuthoredItem(kind: .song) }
            // … New Bible / New Text / Import Media… / New Playlist
        } label: {
            Label("Add", systemImage: "plus")
        }
        Button { showInspector.toggle() } label: { Label("Inspector", systemImage: "sidebar.trailing") }
    }
}
```

**TypeScript equivalent**

```tsx
// analogy: @ToolbarContentBuilder var -> a function returning toolbar items
function toolbarContent(): JSX.Element {
  return (
    <>
      <ToolbarItem placement="navigation">
        <button onClick={() => openEditor(selectedItem)} disabled={selectedItem == null}>
          <Icon name="square.and.pencil" /> Edit
        </button>
      </ToolbarItem>

      <ToolbarItem placement="status">
        {/* analogy: Menu -> dropdown menu */}
        <Menu label={
          <Label
            icon={output.isActive ? "tv.fill" : "tv"}
            text={output.isActive ? output.activeScreenName : "Start Output"}
          />
        }>
          {output.isActive && <>
            <button onClick={() => output.stop()}>Stop Output</button>
            <Divider />
          </>}
          {output.screens.length === 0
            ? <Text>No displays detected</Text>
            : output.screens.map(screen => (
                <button key={screen.id} onClick={() => output.start(screen.id)}>
                  <Icon name="display" /> {screen.name}
                </button>
              ))}
        </Menu>
      </ToolbarItem>

      <ToolbarItemGroup placement="primaryAction">
        <Menu label={<Label icon="plus" text="Add" />}>
          <button onClick={() => newAuthoredItem("song")}>New Song</button>
          {/* … New Bible / New Text / Import Media… / New Playlist */}
        </Menu>
        <button onClick={() => setShowInspector(v => !v)}>
          <Icon name="sidebar.trailing" /> Inspector
        </button>
      </ToolbarItemGroup>
    </>
  );
}
```

**Swift syntax:**
- `@ToolbarContentBuilder private var toolbarContent: some ToolbarContent` — like `@ViewBuilder` but for toolbar items; lets the property list/branch items. TS analog: a function returning a fragment of toolbar nodes.
- `.disabled(selectedItem == nil)` — a modifier toggling the enabled state. TS analog: `disabled={selectedItem == null}`.
- `ForEach(output.screens) { screen in ... }` — `.map` with a named param. TS analog: `output.screens.map(screen => ...)`.
- `showInspector.toggle()` — flips a `Bool` in place. TS analog: `setShowInspector(v => !v)`.

### Opening the editor

```swift
private func openSlideEditor(id: PersistentIdentifier) {
    if let slide = modelContext.model(for: id) as? Slide, let item = slide.item {
        openWindow(id: "slide-editor", value: item.persistentModelID)
    } else if modelContext.model(for: id) is Item {
        openWindow(id: "slide-editor", value: id)
    } else {
        openEditor(for: selectedItem)
    }
}
```

**TypeScript equivalent**

```ts
function openSlideEditor(id: PersistentIdentifier): void {
  const model = modelContext.model(id);
  // analogy: `as? Slide` -> safe downcast returning null if the type doesn't match
  if (model instanceof Slide && model.item) {
    openWindow("slide-editor", model.item.persistentModelID);
  } else if (model instanceof Item) {
    openWindow("slide-editor", id);
  } else {
    openEditor(selectedItem);
  }
}
```

**Swift syntax:**
- `if let slide = modelContext.model(for: id) as? Slide, let item = slide.item` — `as?` is a **safe downcast** (yields `nil` if the type doesn't match), chained with another optional binding; both must succeed. TS analog: `if (model instanceof Slide && model.item)`.
- `modelContext.model(for: id) is Item` — `is` runtime type test. TS analog: `instanceof Item`.

The grid hands back a *program-slide* id. This resolves it to its parent `Item` and opens the editor window keyed on that item (`openWindow(id:value:)`). The editor is keyed on the item, so reopening the same item raises its existing window rather than spawning a duplicate.

### Creating content

`newAuthoredItem(kind:)` inserts a fresh `Item`, gives it the default theme and sensible `linesPerSlide`, seeds the right scaffolding (a blank verse for songs, a translation+empty reference for Bible, empty body for text), selects it, and **opens the editor immediately** so the operator can start authoring. `importMedia()` runs an `NSOpenPanel` file picker, copies the file into the media library via `MediaStorage.importFile`, and inserts a `.media` item (or `NSSound.beep()`s on failure).

```swift
private func newAuthoredItem(kind: ItemKind) {
    let title: String
    switch kind {
    case .song:  title = "Untitled Song"
    case .bible: title = "Untitled Passage"
    case .text:  title = "Untitled Text"
    case .media: return
    }
    let item = Item(kind: kind, title: title)
    item.theme = Theme.makeDefault()
    item.linesPerSlide = kind == .song ? 2 : 3
    modelContext.insert(item)
    switch kind {
    case .song:
        item.songSections = [SongSection(kind: .verse, number: 1, order: 0, lyrics: "")]
    case .bible:
        item.bibleTranslation = BibleSeeder.bundledTranslations().first?.id ?? "kjv"
        item.bibleReference = ""
    case .text:
        item.bodyText = ""
    case .media:
        break
    }
    selectedID = item.persistentModelID
    openEditor(for: item)
}
```

**TypeScript equivalent**

```ts
function newAuthoredItem(kind: ItemKind): void {
  let title: string;
  switch (kind) {
    case "song":  title = "Untitled Song"; break;
    case "bible": title = "Untitled Passage"; break;
    case "text":  title = "Untitled Text"; break;
    case "media": return;
  }
  const item = new Item(kind, title);
  item.theme = Theme.makeDefault();
  item.linesPerSlide = kind === "song" ? 2 : 3;
  modelContext.insert(item);

  switch (kind) {
    case "song":
      item.songSections = [new SongSection("verse", 1, 0, "")];
      break;
    case "bible":
      item.bibleTranslation = BibleSeeder.bundledTranslations()[0]?.id ?? "kjv";
      item.bibleReference = "";
      break;
    case "text":
      item.bodyText = "";
      break;
    case "media":
      break;
  }
  setSelectedID(item.persistentModelID);
  openEditor(item);
}
```

**Swift syntax:**
- `switch kind { case .song: ...; case .media: return }` — exhaustive enum switch; each case auto-breaks. `return` early-exits the whole function. TS analog: `switch` with explicit `break`/`return`.
- `kind == .song ? 2 : 3` — ternary on an enum case. TS analog: `kind === "song" ? 2 : 3`.
- `BibleSeeder.bundledTranslations().first?.id ?? "kjv"` — `.first?` optional chaining on a possibly-empty array, with `??` fallback. TS analog: `arr[0]?.id ?? "kjv"`.

### Helper types at the bottom

`WindowRef` is a weak holder so the key-monitor closure reads the *current* window identity at fire time. `WindowAccessor` is a tiny `NSViewRepresentable` that resolves the hosting `NSWindow` and reports it back via the `onResolve` callback — that's how the view learns its own window without an `NSWindowDelegate`.

```swift
final class WindowRef {
    weak var window: NSWindow?
}

struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onResolve(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onResolve(nsView.window) }
    }
}
```

**TypeScript equivalent**

```ts
// analogy: a class is a reference type; `weak` ≈ a WeakRef so it doesn't pin the window alive
class WindowRef {
  window: WeakRef<NSWindow> | null = null;
}
```

```tsx
// analogy: NSViewRepresentable -> a wrapper bridging a non-React DOM widget
function WindowAccessor({ onResolve }: { onResolve: (w: NSWindow | null) => void }) {
  const ref = useRef<HTMLDivElement>(null);
  // DispatchQueue.main.async { ... } -> defer to the next tick (queueMicrotask)
  useEffect(() => { queueMicrotask(() => onResolve(getHostWindow(ref.current))); });
  return <div ref={ref} style={{ display: "none" }} />;
}
```

**Swift syntax:**
- `final class WindowRef` — `final` = not subclassable; `class` = reference type. TS analog: a `class` (objects are reference types by default).
- `weak var window: NSWindow?` — a weak reference that auto-nils when the window is freed; prevents a retain cycle. TS analog: `WeakRef`.
- `let onResolve: (NSWindow?) -> Void` — a stored closure prop (`(w) => void`). TS analog: a callback prop.
- `DispatchQueue.main.async { ... }` — run on the next main-thread tick. TS analog: `queueMicrotask(...)` / `setTimeout(..., 0)`.

## How it connects

- **`LiveState` (`live`)** drives all live behavior: `arm`, `next`/`previous`, `goLive(id:)`, `setPanic`, and the read-only `liveSlideID` / `nextProgramSlide` used for prewarming.
- **`OutputController` (`output`)** owns the audience window: `start(screenID:)`, `stop()`, `screens`, `isActive`, `activeScreenName`, `activeOutputPixelSize`.
- **`@Query`** supplies the live `items` and `playlists` lists; **`modelContext`** is used to insert/delete models and resolve ids.
- **Child views:** `SidebarView` (left), `detailPane` → either `PlaylistSlidesView` (a playlist) or `SlideGridView` (a single item), and `InspectorView` (right). Thumbnails in the grids render through the shared `SlideRenderer`.
- **The editor window** is reached via `openWindow(id: "slide-editor", value:)`; when it closes it posts `.slideEditorDidClose`, which triggers a re-arm here.
- **Prewarmers:** `VideoPrewarmer.shared` and `SlidePrewarmer.shared` are nudged whenever the live slide changes.

## Gotchas / why it matters

- **Text-field focus guard** — the key monitor passes keys through when a text field is focused, so typing in the search box never accidentally advances slides or blanks the screen.
- **Window-identity guard** — keys only drive the program when the *operator* window is key. The editor is a separate window (Phase 8.4), so editing must not touch the audience output. The `WindowRef`/`WindowAccessor` dance exists purely to make this check reliable.
- **Arm vs. go-live** — `arm` only *loads* slides; nothing reaches the audience until the operator clicks a thumbnail or presses a navigation key. This is the value-snapshot separation: `LiveState` works on immutable snapshots, so editing a model can't change what's live mid-service.
- **Main-thread AppKit callbacks** — `MainActor.assumeIsolated` is used because the key monitor is known to fire on the main thread; it lets the closure touch main-actor state directly.
- **Performance for Sunday** — search is debounced and memoized, and the next slide/video is prewarmed at output resolution so advancing never pays for a fresh render mid-switch.
