# `JerusalemApp.swift`

> The app's entry point: declares the app's windows (the operator window and a dedicated slide-editor window) and wires up the shared state and database.

**Location:** `Sources/Jerusalem/JerusalemApp.swift`
**Role:** app entry point

## What it does (plain English)

This is the `@main` struct — the program's starting point, like `index.tsx` mounting your root component. It builds the app's two shared stores (`LiveState` and `OutputController`) and the SwiftData database **once**, then declares the app's windows and injects those shared objects into them.

There are two windows declared:

1. The **operator window** (`id: "operator"`) — the main control surface, hosting `OperatorView`.
2. The **slide editor window** (`id: "slide-editor"`) — a separate window that's the single place to edit an item (title, content, and slide design). It's *keyed on an item id*, meaning it's opened by passing which item to edit.

The crucial pattern here is **state injection**: `live` and `output` are created once and passed down with `.environment(...)`; descendant views read them via `@Environment(Type.self)`. That's the SwiftUI equivalent of React Context / a global store. The same database `container` is attached to both windows via `.modelContainer(...)`, so edits made in the editor window are reflected in the operator window.

## Swift you'll meet in this file

| Swift | JS/TS analogy |
|---|---|
| `@main struct JerusalemApp: App` | The program entry point; conforms to the `App` protocol. Like the root that boots the UI. |
| `var body: some Scene` | Declares the app's **windows**. (`some Scene` = "some concrete Scene type" — an opaque return type.) |
| `WindowGroup(...) { ... }` | Declares a window and its root SwiftUI view. |
| `@State private var live: LiveState` | Owned, persistent state held by the app — like `useState`, but here it owns the shared store object. |
| `@Observable class LiveState` (defined elsewhere) | A shared, observable store — injected via `.environment(...)`, read via `@Environment(...)`. Like React Context. |
| `private let container = ...` | A constant property (`const`), built once at startup. |
| `init() { ... }` | A constructor. |
| `_live = State(initialValue: ...)` | The low-level way to initialize a `@State` property inside `init` (the `_` prefix is the underlying storage). |
| `.environment(live)` | Inject a value into the SwiftUI environment for descendants — like a Context Provider. |
| `.modelContainer(container)` | Attach the SwiftData DB to this window's view tree. |
| `for: PersistentIdentifier.self` + `{ $itemID in ... }` | A window type that carries a value (the item's id) and binds it as `$itemID` to the window's content. |

## Code walkthrough

### The entry point and its state

```swift
@main
struct JerusalemApp: App {
    @State private var live: LiveState
    @State private var output: OutputController
    private let container = Persistence.makeContainer()
```

`@main` marks this as where the program starts. It owns three things: the `live` store (what's on the audience screen), the `output` controller (the audience window placement), and the SwiftData `container` (built once via `Persistence.makeContainer()`).

### The initializer

```swift
init() {
    let liveState = LiveState()
    _live = State(initialValue: liveState)
    _output = State(initialValue: OutputController(live: liveState))
}
```

Both stores are created here. Note `output` is given the *same* `liveState` instance — the output controller observes live state. The `_live = State(initialValue:)` form is just how you assign a `@State` property from inside `init` (`_live` is the property's underlying storage box). In JS terms: `this.live = liveState; this.output = new OutputController(liveState)`.

### Declaring the windows

```swift
var body: some Scene {
    WindowGroup("Jerusalem", id: "operator") {
        OperatorView()
            .environment(live)
            .environment(output)
    }
    .defaultSize(width: 1280, height: 800)
    .windowToolbarStyle(.unified)
    .modelContainer(container)
```

`body` lists the app's windows. The first `WindowGroup` is the operator window: its root view is `OperatorView`, and `.environment(live)` / `.environment(output)` inject the shared stores so any descendant can read them. The modifiers set a default window size, a native unified toolbar, and attach the database.

```swift
    WindowGroup("Slide Editor", id: "slide-editor", for: PersistentIdentifier.self) { $itemID in
        SlideEditorWindowRoot(itemID: itemID)
            .environment(live)
            .environment(output)
    }
    .defaultSize(width: 1320, height: 820)
    .windowToolbarStyle(.unified)
    .modelContainer(container)
}
```

The second `WindowGroup` is the editor. The `for: PersistentIdentifier.self` part makes it a **value-carrying** window: it's opened with a specific item id (the comment notes the operator calls `openWindow(id:value:)` carrying the item's `PersistentIdentifier`). That id arrives as `$itemID` and is passed to `SlideEditorWindowRoot`. Carrying the *item's* id (not a slide's) means the editor can open even before any slides exist. It shares the **same** `container`, so edits flow back to the operator window when the editor closes.

## How it connects

- **`Persistence.makeContainer()`** builds the DB this app injects into both windows.
- **`LiveState`** and **`OutputController`** are the shared stores created here and read elsewhere via `@Environment(LiveState.self)` / `@Environment(OutputController.self)`.
- **`OperatorView`** is the operator window's root; **`SlideEditorWindowRoot`** is the editor window's root.
- The editor is launched from the operator via `openWindow(id: "slide-editor", value: <itemID>)`.

## Gotchas / why it matters

- **Single source of truth, injected once.** `live`, `output`, and `container` are all created exactly once here and shared via the environment. Creating extra instances elsewhere would split the app's state — don't.
- **Both windows share one container.** That shared `container` is why editor changes appear in the operator window. Crucial for the edit-then-present workflow.
- **Editor is keyed on the *item* id, not a slide.** This lets the editor open for an item that has no slides yet — important for authoring from scratch.
- **`.environment(...)` is the injection contract.** Descendant views expect `LiveState` and `OutputController` in the environment; that's set up here for each window.
