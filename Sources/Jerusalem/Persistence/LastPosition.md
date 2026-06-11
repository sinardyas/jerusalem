# `LastPosition.swift`

> Persists which item or playlist the operator had selected when the app last closed, so it reopens on the same selection.

**Location:** `Sources/Jerusalem/Persistence/LastPosition.swift`
**Role:** preference persistence helper (namespace of pure functions)

## What it does (plain English)

When the operator closes the app, this remembers **what was selected** — a specific song/verse item, or a playlist. On next launch the app re-selects it, so you "reopen where you left off."

Importantly, it only restores the *selection*, not the live playback position inside a program. The operator always explicitly starts playback on launch; auto-resuming a live slide on the audience screen would be surprising (and risky on Sunday morning).

The value is stored in `UserDefaults` (macOS's small key/value preferences store — like `localStorage`), encoded as JSON. It deliberately stores the **stable `UUID`** of the item or playlist, not SwiftData's internal `PersistentIdentifier`, because that internal id is process-local and gets regenerated every relaunch — it wouldn't survive a restart.

On launch, `resolve(...)` turns the saved `UUID` back into a live SwiftData `PersistentIdentifier` the operator UI can use as its selection — and returns `nil` if that row was deleted while the app was closed.

## Swift you'll meet in this file

| Swift | JS/TS analogy |
|---|---|
| `enum LastPosition { static ... }` | Caseless enum used as a **namespace** of pure functions — `export const LastPosition = { ... }`. |
| `private static let key = "..."` | A module-private constant (`const`). `let` = `const`. |
| `enum Selection: Codable { case item(UUID); case playlist(UUID) }` | A real (case-ful) enum that **carries data** — like a TS discriminated union: `{ kind: 'item', id } \| { kind: 'playlist', id }`. `Codable` = JSON-serializable. |
| `UserDefaults.standard` | The OS preferences store — like `localStorage`. |
| `UUID` | A unique id (string-like). |
| `JSONEncoder` / `JSONDecoder` | `JSON.stringify` / `JSON.parse`, but type-safe. |
| `Selection?` and `guard let selection else { ... }` | `Selection \| null`; an early-return null check that binds the non-null value. |
| `try?` | Run a throwing call; on error yield `nil`. |
| `@MainActor` | Must run on the main (UI) thread. |
| `FetchDescriptor<Item>` + `#Predicate` | A SwiftData query object with a type-checked `where` clause — closest to a Prisma `findFirst({ where: ... })`. |
| `switch selection { case .item(let uuid): ... }` | A `switch` that **destructures** the enum's associated value into `uuid`. |

## Code walkthrough

### The storage key and the selection type

```swift
private static let key = "jerusalem.lastSelection.v1"

enum Selection: Codable, Equatable, Sendable {
    case item(UUID)
    case playlist(UUID)
}
```

`key` is the `UserDefaults` slot (note the `v1` — room to change the format later). `Selection` is a tagged union: it's *either* an item id *or* a playlist id. Because it's `Codable`, Swift auto-generates JSON encode/decode for it.

### `save`

```swift
static func save(_ selection: Selection?) {
    let defaults = UserDefaults.standard
    guard let selection else {
        defaults.removeObject(forKey: key)
        return
    }
    if let data = try? JSONEncoder().encode(selection) {
        defaults.set(data, forKey: key)
    }
}
```

Passing `nil` clears the saved selection (like `localStorage.removeItem`). Otherwise it JSON-encodes the selection and writes it. `guard let selection else { ... }` here unwraps the optional argument; the `else` branch handles the "cleared" case.

### `load`

```swift
static func load() -> Selection? {
    guard let data = UserDefaults.standard.data(forKey: key),
          let selection = try? JSONDecoder().decode(Selection.self, from: data)
    else { return nil }
    return selection
}
```

Reads the bytes, decodes them back into a `Selection`, and returns `nil` if either step fails. The two `let` bindings in one `guard` are chained AND-conditions — both must succeed.

### `resolve`

```swift
@MainActor
static func resolve(_ selection: Selection?,
                    in context: ModelContext) -> PersistentIdentifier? {
    guard let selection else { return nil }
    switch selection {
    case .item(let uuid):
        var descriptor = FetchDescriptor<Item>(
            predicate: #Predicate { $0.uuid == uuid })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.persistentModelID
    case .playlist(let uuid):
        var descriptor = FetchDescriptor<Playlist>(
            predicate: #Predicate { $0.uuid == uuid })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.persistentModelID
    }
}
```

This bridges the *stable* `UUID` back to a *runtime* SwiftData id. The `switch` destructures the saved selection into its `uuid`, then runs a query: "find the `Item` (or `Playlist`) whose `uuid` matches," limited to one row. `#Predicate { $0.uuid == uuid }` is a type-checked query closure (`$0` is the row being tested), comparable to a Prisma `where`. The chain `(try? context.fetch(descriptor))?.first?.persistentModelID` reads "run the fetch (nil on error) → take the first result (nil if empty) → grab its runtime id" — returning `nil` if the row was deleted while the app was closed.

## How it connects

- **`Item` / `Playlist`** are the SwiftData `@Model` types whose stable `uuid` is stored and whose `persistentModelID` is returned.
- **`ModelContext`** (from `Persistence.makeContainer`) is the session the `resolve` query runs against.
- The operator UI calls `save(...)` when selection changes and `resolve(...)` on launch to seed its `@State selectedID`.

## Gotchas / why it matters

- **Stable UUID, not `PersistentIdentifier`.** SwiftData's `PersistentIdentifier` is process-local and regenerated each launch — storing it would silently break resume. The whole reason this file exists is to translate between the durable `UUID` and the per-run id.
- **Selection only, never live position.** Restoring a *live* slide could put unexpected content on the audience screen at launch. This intentionally restores only what's selected; the operator presses play.
- **Graceful on deletion.** If the saved item/playlist was deleted between sessions, `resolve` returns `nil` rather than crashing — the app just opens with nothing selected.
