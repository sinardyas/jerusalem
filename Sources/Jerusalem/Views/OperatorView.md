# `OperatorView.swift`

> The top-level operator (live-control) window — the control surface used live on Sunday morning to drive what's on the audience screen.

**Location:** `Sources/Jerusalem/Views/OperatorView.swift`
**Role:** SwiftUI view — the operator window (the main window shell)

## What it does (plain English)

This is the **main window** the operator stares at during a service. On the left is the library/playlist sidebar, in the middle is a grid of slide thumbnails, and on the right is an inspector that mirrors what's live. The operator picks a song (or playlist), then drives the live program **from the keyboard**: arrow keys / space advance slides, and the letters **B / C / L** are panic buttons (Black / Clear / Logo) that instantly blank or override the audience screen.

Crucially, this window is **presentation/live-control only**. As of Phase 8.5 all *editing* (title, lyrics, slide design) moved to a separate slide-editor window. This file opens that editor window when asked, but never edits content inline. That separation is a safety feature: fiddling with content can't change what the congregation sees.

The window also handles the plumbing that keeps things fast and reliable: a debounced search box, a memoized search index so filtering doesn't re-scan every slide on each keystroke, render-ahead/prewarming of the *next* slide and video, and restoring the last selection on relaunch so reopening the app lands where the service left off.

## Swift you'll meet in this file

- **`struct OperatorView: View { var body: some View }`** — a SwiftUI view is a value-type `struct` with a `body` property. Think React function component; `body` is the returned JSX. `some View` is an opaque return type ("returns *some* concrete View, the exact type is hidden").
- **`@Query(sort: \Item.title) private var items: [Item]`** — a *live database query* (SwiftData). Like a data hook that auto-re-renders when the underlying rows change. `\Item.title` is a key path (think `item => item.title`).
- **`@Environment(LiveState.self) private var live`** — React-Context-style dependency injection. `LiveState` and `OutputController` are created once at app startup and read here by type. `@Environment(\.modelContext)` is the SwiftData write session; `@Environment(\.openWindow)` is the system function for opening another window.
- **`@State private var showInspector = true`** — `useState`. Local mutable UI state that triggers re-render on change.
- **`$searchText`** — the `$` prefix turns a `@State` value into a two-way **Binding** (a read/write handle), like passing both `value` and `onChange` as one prop.
- **`Task<Void, Never>?`** — a handle to an async task (`T?` means "T or null"). Used to cancel an in-flight debounce.
- **`NavigationSplitView { sidebar } detail: { ... }`** — a multi-column app shell (sidebar + content/detail). `.inspector(...)` adds a trailing panel; `.toolbar { }` adds the window toolbar; `.searchable(...)` adds the system search field.
- **`if let selectedItem { ... } else { ... }`** — optional binding: runs the first branch only when the optional is non-null, binding the unwrapped value.
- **`NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in ... }`** — AppKit. Installs a window-local keydown listener, like `addEventListener('keydown')`. Returning `nil` swallows the key; returning `event` lets it pass through.
- **`MainActor.assumeIsolated { }`** — "this callback already runs on the main thread, so treat it as main-thread-isolated." Lets the closure touch main-thread-only state without `await`.
- **`class WindowRef { weak var window: NSWindow? }`** — a `class` is a reference type (shared, like a JS object). `weak` avoids a retain cycle so it doesn't keep the window alive.
- **`NSViewRepresentable`** — a bridge that wraps an AppKit `NSView` so it can live inside SwiftUI.

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

Read this like nested JSX: a split view with the `SidebarView` on the left and `detailPane` in the middle, the `InspectorView` attached as a trailing panel, the toolbar attached, and a search field placed in the sidebar.

The chained `.onChange` / `.onReceive` / `.onAppear` / `.onDisappear` modifiers wire the lifecycle:

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

This is the live-control wiring, and there are two guards that matter:

1. **`guard NSApp.keyWindow === windowRef.window else { return event }`** — only drive the program when the *operator window* is the key (focused) window. If an editor window is focused, the key passes through unchanged. Editing must never advance or blank the audience screen.
2. **`if NSApp.keyWindow?.firstResponder is NSText { return event }`** — if a text field (like the search box) is focused, let the key through so typing works. `is NSText` is a type check.

Returning `nil` **consumes** the key (it stops here); returning `event` **lets it bubble**. The first `switch` maps macOS key codes for space/arrows to next/previous; the second maps the letters `b`/`c`/`l` to the three panic states. `removeKeyMonitor()` (called from `.onDisappear`) tears it down with `NSEvent.removeMonitor`.

### The toolbar

`toolbarContent` (a `@ToolbarContentBuilder`) lays out:
- **Edit** button (leading) → `openEditor(for: selectedItem)`, disabled when nothing is selected. This is how you reach the slide-editor window.
- **Output** menu (status) → start output on a chosen `NSScreen`, or stop it; shows "No displays detected" when none exist.
- **Add** menu + **Inspector** toggle (primary action) → create a new Song/Bible/Text item, import media, or create a playlist.

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

The grid hands back a *program-slide* id. This resolves it to its parent `Item` and opens the editor window keyed on that item (`openWindow(id:value:)`). The editor is keyed on the item, so reopening the same item raises its existing window rather than spawning a duplicate.

### Creating content

`newAuthoredItem(kind:)` inserts a fresh `Item`, gives it the default theme and sensible `linesPerSlide`, seeds the right scaffolding (a blank verse for songs, a translation+empty reference for Bible, empty body for text), selects it, and **opens the editor immediately** so the operator can start authoring. `importMedia()` runs an `NSOpenPanel` file picker, copies the file into the media library via `MediaStorage.importFile`, and inserts a `.media` item (or `NSSound.beep()`s on failure).

### Helper types at the bottom

`WindowRef` is a weak holder so the key-monitor closure reads the *current* window identity at fire time. `WindowAccessor` is a tiny `NSViewRepresentable` that resolves the hosting `NSWindow` and reports it back via the `onResolve` callback — that's how the view learns its own window without an `NSWindowDelegate`.

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
