# `SlideEditorWindowRoot.swift`

> The root view of the dedicated slide-editor window: it takes an *item's* ID, re-resolves the live `Item` from the SwiftData context, hosts `SlideEditorView`, and notifies the operator window to re-arm the live program when the editor closes.

**Location:** `Sources/Jerusalem/Editor/SlideEditorWindowRoot.swift`
**Role:** window root

## What it does (plain English)

The slide editor lives in its own macOS window (a `WindowGroup`, Phase 8.5). A window scene can only carry a tiny, serializable payload — here, the **item's `PersistentIdentifier`** — not a live model object. So this root view's job is to take that ID and look the real `Item` back up out of the shared SwiftData container, then render the actual editor.

It deliberately keys on the *item*, not a slide, because the editor must open even for an item that has **no slides yet** (e.g. a brand-new song — you type lyrics and `ContentRebuilder` materializes slides). If the item resolves, it shows `SlideEditorView` opened on the item's first slide (or none); if it can't (deleted, bad ID), it shows a friendly "Item Unavailable" placeholder instead of crashing.

It also defines and fires a notification: when the editor window closes, it posts `.slideEditorDidClose` so the operator window can re-arm `LiveState` with the possibly-edited program (the audience output doesn't auto-follow editor changes — see the edit/live separation rule).

## Swift you'll meet in this file

- `extension Notification.Name { static let slideEditorDidClose = … }` — defines a named notification constant (a typed string key), like declaring an event name. `NotificationCenter` ≈ a global event bus / `EventEmitter`.
- `struct SlideEditorWindowRoot: View { var body: some View }` — a SwiftUI view ≈ React component.
- `let itemID: PersistentIdentifier?` — an optional SwiftData row id (`T | null`); `@Environment(\.modelContext)` — the injected SwiftData session.
- `modelContext.model(for: itemID) as? Item` — fetch a model by its id, then **conditionally cast** (`as?` returns nil if it isn't an `Item`).
- `if let itemID, let item = … as? Item { … } else { … }` — chained optional binding; both must succeed or you fall to `else`.
- `Group { … }` — a transparent container to return one of several views from a conditional.
- `.onDisappear { … }` — a teardown effect when the view leaves the screen.

## Code walkthrough

### The notification name

```swift
extension Notification.Name {
    static let slideEditorDidClose = Notification.Name("id.soechi.slideEditorDidClose")
}
```

Just a constant for the event name, namespaced with a reverse-DNS string to avoid collisions. The operator window subscribes to this elsewhere.

### Resolving the item and choosing what to show

```swift
var body: some View {
    Group {
        if let itemID, let item = modelContext.model(for: itemID) as? Item {
            SlideEditorView(item: item, slideID: item.orderedSlides.first?.persistentModelID)
        } else {
            ContentUnavailableView("Item Unavailable",
                                   systemImage: "rectangle.slash",
                                   description: Text("This item could not be loaded for editing."))
        }
    }
    .onDisappear { NotificationCenter.default.post(name: .slideEditorDidClose, object: nil) }
}
```

- **The double `if let`** unwraps the optional id *and* fetches+casts the model in one condition. `modelContext.model(for:)` re-hydrates the live `Item` from the shared container — this is what turns the serializable id back into a usable model object.
- **`slideID: item.orderedSlides.first?.persistentModelID`** opens the editor on the first slide if there is one. The `?.` means: if there are no slides, pass `nil` and let `SlideEditorView` show its empty state. (Recall `SlideEditorView` is built to open on an item with zero slides.)
- **The `else` branch** is the safety net: a stale window restored against a deleted item shows a placeholder rather than crashing.
- **`.onDisappear`** posts `.slideEditorDidClose` exactly once when the window closes, telling the operator side to re-arm the program.

## How it connects

- **Upstream:** a `WindowGroup` scene (defined in the app) instantiates this with the selected item's `PersistentIdentifier`. Window scenes can only carry such lightweight, codable values — which is *why* this re-resolution step exists.
- **Downstream:** it constructs and hosts `SlideEditorView`, handing it the resolved live `Item` and an optional starting `slideID`. From there the editor owns all interaction.
- **Sideways:** the `.slideEditorDidClose` post is consumed by the operator window to call something like `LiveState`'s arm/re-arm so the audience output picks up edits — honoring the rule that the live screen only changes when the operator acts.

## Gotchas / why it matters

- **Pass an ID, not a model, into a window.** Window scenes restore lazily and across launches; a `@Model` can't ride along, but its `PersistentIdentifier` can. This view is the bridge that turns the id back into the object.
- **Keyed on the item, not a slide — on purpose.** New items have no slides; opening on the item lets the content rail + `ContentRebuilder` create them. Don't refactor this to require a slide id.
- **Always have a fallback.** The `else` placeholder is what keeps a dangling/deleted reference from crashing the editor — directly serving the "never fail" promise.
- **The close notification is load-bearing.** Without the `.onDisappear` post, edits made in the window wouldn't be reflected in the live program until something else re-armed it.
