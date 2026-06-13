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
| `@main struct JerusalemApp: App` | The program entry point; conforms to the `App` protocol (shape: `@main struct X: App`). Like the root that boots the UI. |
| `var body: some Scene` | Declares the app's **windows**. (`some Scene` = "some concrete Scene type" — an opaque return type, like returning `Scene` without naming the exact class.) |
| `WindowGroup(...) { ... }` | Declares a window and its root SwiftUI view (trailing closure is the content). |
| `@State private var live: LiveState` | Owned, persistent state held by the app — like `useState`, but here it owns the shared store object. |
| `@Observable class LiveState` (defined elsewhere) | A shared, observable store — injected via `.environment(...)`, read via `@Environment(...)`. Like a React Context value. |
| `private let container = ...` | A constant property, built once at startup. Shape: `let name = value`. |
| `init() { ... }` | A constructor. |
| `_live = State(initialValue: ...)` | The low-level way to initialize a `@State` property inside `init` (the `_` prefix is the underlying storage box). |
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

**TypeScript equivalent**

```ts
// analogy: the root bootstrap — like the module that ReactDOM-renders the app.
// @State-owned stores ≈ singletons created once and provided via Context.
class JerusalemApp /* : App */ {
  private live!: LiveState;       // @State private var live
  private output!: OutputController;
  private readonly container = Persistence.makeContainer();  // built once
}
```

`@main` marks this as where the program starts. It owns three things: the `live` store (what's on the audience screen), the `output` controller (the audience window placement), and the SwiftData `container` (built once via `Persistence.makeContainer()`).

**Swift syntax:**
- `@main` — marks the program's entry point (the runtime starts here). Like the module React renders at the root.
- `struct JerusalemApp: App` — a `struct` (value type) that **conforms to** the `App` protocol (the `: App` part). Conforming to `App` is what requires a `body` returning scenes.
- `@State private var live: LiveState` — `@State` is SwiftUI-owned, persistent storage tied to this view/app's lifetime; here it owns a shared store. `var` (mutable). Roughly `useState`, but holding an object the app owns. The type is declared without an initial value because `init()` sets it.
- `private let container = Persistence.makeContainer()` — a `let` (constant) stored property initialized inline, run once when the app is created.

### The initializer

```swift
init() {
    let liveState = LiveState()
    _live = State(initialValue: liveState)
    _output = State(initialValue: OutputController(live: liveState))
}
```

**TypeScript equivalent**

```ts
// analogy: const live = useMemo(() => new LiveState(), []) — created once, then shared.
constructor() {
  const liveState = new LiveState();
  this.live = liveState;
  this.output = new OutputController(liveState);  // output observes the SAME liveState
}
```

Both stores are created here. Note `output` is given the *same* `liveState` instance — the output controller observes live state. The `_live = State(initialValue:)` form is just how you assign a `@State` property from inside `init` (`_live` is the property's underlying storage box). In JS terms: `this.live = liveState; this.output = new OutputController(liveState)`.

**Swift syntax:**
- `init()` — the constructor (no `function`/`constructor` keyword; just `init`).
- `_live = State(initialValue: liveState)` — every `@State var live` has a hidden backing store named `_live`. Inside `init` you can't assign `live` directly, so you set the backing `_live` to a `State` value. The `_`-prefixed name is the property-wrapper's storage. There's no TS analog; conceptually it's `this.live = liveState`.

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

**TypeScript equivalent**

```ts
// analogy: body returns the app's windows; .environment(...) ≈ Context.Provider;
// .modelContainer(...) ≈ providing the DB client to this subtree.
get body() {
  return [
    window({ title: "Jerusalem", id: "operator" }, () => (
      <EnvironmentProvider value={live}>
        <EnvironmentProvider value={output}>
          <OperatorView />
        </EnvironmentProvider>
      </EnvironmentProvider>
    ))
      .defaultSize(1280, 800)
      .windowToolbarStyle("unified")
      .modelContainer(container),
    // ...second window below
  ];
}
```

`body` lists the app's windows. The first `WindowGroup` is the operator window: its root view is `OperatorView`, and `.environment(live)` / `.environment(output)` inject the shared stores so any descendant can read them. The modifiers set a default window size, a native unified toolbar, and attach the database.

**Swift syntax:**
- `var body: some Scene` — a **computed property** (no `()`; it recomputes when read) returning `some Scene`. `some Scene` is an **opaque return type**: "a single concrete type conforming to `Scene`, hidden from callers." Like declaring a return type of `Scene` without naming the exact class. (`some View` is the same idea for views.)
- `WindowGroup("Jerusalem", id: "operator") { OperatorView() ... }` — declares a window; the **trailing closure** `{ ... }` is its root content. A trailing closure is a closure written *after* the call's parens (here the parens are the title/id args). Like passing a render function as the last argument.
- `.environment(live)` — a **view modifier** that injects `live` into the environment for all descendants; they read it back with `@Environment(LiveState.self)`. This is the Context.Provider half of React Context. Modifiers chain (each returns a new view).
- `.modelContainer(container)` — injects the SwiftData container into this scene's view tree (so `@Query`/`@Environment(\.modelContext)` work below). Like providing a DB client to a subtree.
- `.defaultSize(...)`, `.windowToolbarStyle(.unified)` — more chained modifiers; `.unified` is leading-dot enum shorthand for `WindowToolbarStyle.unified`.

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

**TypeScript equivalent**

```ts
// analogy: a window "route" parameterized by an item id passed when it's opened.
window({ title: "Slide Editor", id: "slide-editor", for: PersistentIdentifier }, ($itemID) => {
  const itemID = $itemID;   // the value the window was opened with (may be null)
  return (
    <EnvironmentProvider value={live}>
      <EnvironmentProvider value={output}>
        <SlideEditorWindowRoot itemID={itemID} />
      </EnvironmentProvider>
    </EnvironmentProvider>
  );
})
  .defaultSize(1320, 820)
  .windowToolbarStyle("unified")
  .modelContainer(container);
```

The second `WindowGroup` is the editor. The `for: PersistentIdentifier.self` part makes it a **value-carrying** window: it's opened with a specific item id (the comment notes the operator calls `openWindow(id:value:)` carrying the item's `PersistentIdentifier`). That id arrives as `$itemID` and is passed to `SlideEditorWindowRoot`. Carrying the *item's* id (not a slide's) means the editor can open even before any slides exist. It shares the **same** `container`, so edits flow back to the operator window when the editor closes.

**Swift syntax:**
- `for: PersistentIdentifier.self` — declares a **value-carrying window**: each instance is parameterized by a `PersistentIdentifier`. `PersistentIdentifier.self` is the *type* (metatype), telling `WindowGroup` what kind of value the window carries. Think of it as a route param's type.
- `{ $itemID in ... }` — a closure whose parameter is `$itemID`. The `$`-prefixed name is a **binding** to the carried value; reading `itemID` (without `$`) inside gives the current value (which may be `nil` if the window opened without one). `x in` is closure-parameter syntax: everything before `in` is the params, after `in` is the body — like `(itemID) => { ... }`.
- `SlideEditorWindowRoot(itemID: itemID)` — passes the resolved id into the editor's root view via a labeled argument.

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
