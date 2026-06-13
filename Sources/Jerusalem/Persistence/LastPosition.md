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
| `enum LastPosition { static ... }` | Caseless `enum` used as a **namespace** of pure functions (shape: `enum Foo { static func bar() }`) — `export const LastPosition = { ... }`. |
| `private static let key = "..."` | A module-private constant. Shape: `static let name = value`. `let` = `const`. |
| `enum Selection: Codable { case item(UUID); case playlist(UUID) }` | A real (case-ful) enum that **carries data** (shape: `enum E { case a(T) }`) — like a TS discriminated union: `{ kind: 'item', id } \| { kind: 'playlist', id }`. `Codable` = JSON-serializable. |
| `UserDefaults.standard` | The OS preferences store — like `localStorage`. |
| `UUID` | A unique id (string-like). |
| `JSONEncoder` / `JSONDecoder` | `JSON.stringify` / `JSON.parse`, but type-safe. |
| `Selection?` and `guard let selection else { ... }` | `Selection \| null`; an early-return null check that binds the non-null value. Shorthand `guard let selection` reuses the same name. |
| `try?` | Run a throwing call; on error yield `nil`. Shape: `try? throwingCall()`. |
| `@MainActor` | Must run on the main (UI) thread. Shape: `@MainActor func`. |
| `FetchDescriptor<Item>` + `#Predicate` | A SwiftData query object with a type-checked `where` clause (shape: `#Predicate { $0.x == y }`) — closest to a Prisma `findFirst({ where: ... })`. |
| `switch selection { case .item(let uuid): ... }` | A `switch` that **destructures** the enum's associated value into `uuid` via `let`. |

## Code walkthrough

### The storage key and the selection type

```swift
private static let key = "jerusalem.lastSelection.v1"

enum Selection: Codable, Equatable, Sendable {
    case item(UUID)
    case playlist(UUID)
}
```

**TypeScript equivalent**

```ts
const key = "jerusalem.lastSelection.v1";

// analogy: a discriminated union; Codable ≈ JSON-serializable.
type Selection =
  | { kind: "item"; id: string }
  | { kind: "playlist"; id: string };
```

`key` is the `UserDefaults` slot (note the `v1` — room to change the format later). `Selection` is a tagged union: it's *either* an item id *or* a playlist id. Because it's `Codable`, Swift auto-generates JSON encode/decode for it.

**Swift syntax:**
- `private static let key = "..."` — `private` (file-scoped), `static` (on the type, not an instance), `let` (constant). The whole thing is a module-private `const`.
- `enum Selection { case item(UUID); case playlist(UUID) }` — a **case-ful** enum whose cases carry *associated values*. `.item(someUUID)` packs a `UUID` inside the `item` case. This is Swift's discriminated union; in TS you'd model it with a `kind` tag + payload.
- `Codable, Equatable, Sendable` — protocols giving free JSON encode/decode (`Codable`), `==` comparison (`Equatable`), and cross-thread safety (`Sendable`).

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

**TypeScript equivalent**

```ts
function save(selection: Selection | null): void {
  const defaults = localStorage;        // analogy: UserDefaults ≈ localStorage
  if (!selection) {                     // guard let ... else { ... return }
    defaults.removeItem(key);
    return;
  }
  try {
    const data = JSON.stringify(selection);  // JSONEncoder().encode
    defaults.setItem(key, data);
  } catch { /* try? swallows the error */ }
}
```

Passing `nil` clears the saved selection (like `localStorage.removeItem`). Otherwise it JSON-encodes the selection and writes it. `guard let selection else { ... }` here unwraps the optional argument; the `else` branch handles the "cleared" case.

**Swift syntax:**
- `guard let selection else { ... }` — **shorthand binding**: when the new constant has the same name as the optional, you can drop `= selection`. Unwraps `selection` (now non-optional below) or runs the `else` (which must exit). TS: `if (!selection) { ...; return; }`.
- `if let data = try? ... { }` — combines optional-binding with `try?`: encode, and only enter the block if it succeeded (non-nil). TS: `try { const data = ...; ... } catch {}`.
- `JSONEncoder().encode(selection)` — serializes a `Codable` value to bytes; can throw. Like `JSON.stringify`.

### `load`

```swift
static func load() -> Selection? {
    guard let data = UserDefaults.standard.data(forKey: key),
          let selection = try? JSONDecoder().decode(Selection.self, from: data)
    else { return nil }
    return selection
}
```

**TypeScript equivalent**

```ts
function load(): Selection | null {
  const data = localStorage.getItem(key);      // .data(forKey:)
  if (!data) return null;
  try {
    return JSON.parse(data) as Selection;       // JSONDecoder().decode
  } catch {
    return null;
  }
}
```

Reads the bytes, decodes them back into a `Selection`, and returns `nil` if either step fails. The two `let` bindings in one `guard` are chained AND-conditions — both must succeed.

**Swift syntax:**
- chained `guard let a = ..., let b = ... else { return nil }` — both bindings must succeed (logical AND); any `nil` triggers the single `else`. Cleaner than nesting two `if`s.
- `JSONDecoder().decode(Selection.self, from: data)` — `Selection.self` passes the *type* to decode into; the decoder reconstructs the enum case from JSON.

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

**TypeScript equivalent**

```ts
// analogy: FetchDescriptor + #Predicate ≈ prisma.item.findFirst({ where: { uuid } }).
function resolve(
  selection: Selection | null,
  context: ModelContext,
): PersistentIdentifier | null {
  if (!selection) return null;
  switch (selection.kind) {
    case "item": {
      const uuid = selection.id;
      const rows = tryOrNull(() =>
        context.fetch({ entity: Item, where: (row) => row.uuid === uuid, limit: 1 })
      );
      return rows?.[0]?.persistentModelID ?? null;
    }
    case "playlist": {
      const uuid = selection.id;
      const rows = tryOrNull(() =>
        context.fetch({ entity: Playlist, where: (row) => row.uuid === uuid, limit: 1 })
      );
      return rows?.[0]?.persistentModelID ?? null;
    }
  }
}
```

This bridges the *stable* `UUID` back to a *runtime* SwiftData id. The `switch` destructures the saved selection into its `uuid`, then runs a query: "find the `Item` (or `Playlist`) whose `uuid` matches," limited to one row. `#Predicate { $0.uuid == uuid }` is a type-checked query closure (`$0` is the row being tested), comparable to a Prisma `where`. The chain `(try? context.fetch(descriptor))?.first?.persistentModelID` reads "run the fetch (nil on error) → take the first result (nil if empty) → grab its runtime id" — returning `nil` if the row was deleted while the app was closed.

**Swift syntax:**
- `switch selection { case .item(let uuid): ... }` — pattern-matching that **destructures** the associated value out of the enum case: `let uuid` binds the `UUID` packed inside `.item(...)`. Swift `switch` over an enum must be exhaustive (covers every case), so no `default` is needed here. TS: `switch (selection.kind)` + reading `selection.id`.
- `var descriptor = FetchDescriptor<Item>(...)` — `var` (mutable, vs `let`) because the next line mutates `descriptor.fetchLimit`. `FetchDescriptor<Item>` is a generic query object typed to the `Item` entity.
- `#Predicate { $0.uuid == uuid }` — a **macro** producing a type-checked query predicate; `$0` is the row under test. The compiler validates `uuid` against the model's fields. Closest to a Prisma `where` clause.
- `descriptor.fetchLimit = 1` — cap the query to one row (like `take: 1` / `LIMIT 1`).
- `(try? context.fetch(descriptor))?.first?.persistentModelID` — a chain: `try?` → array-or-nil; `?.first` → first element or nil; `?.persistentModelID` → its runtime id or nil. Any nil short-circuits the whole chain to nil.

## How it connects

- **`Item` / `Playlist`** are the SwiftData `@Model` types whose stable `uuid` is stored and whose `persistentModelID` is returned.
- **`ModelContext`** (from `Persistence.makeContainer`) is the session the `resolve` query runs against.
- The operator UI calls `save(...)` when selection changes and `resolve(...)` on launch to seed its `@State selectedID`.

## Gotchas / why it matters

- **Stable UUID, not `PersistentIdentifier`.** SwiftData's `PersistentIdentifier` is process-local and regenerated each launch — storing it would silently break resume. The whole reason this file exists is to translate between the durable `UUID` and the per-run id.
- **Selection only, never live position.** Restoring a *live* slide could put unexpected content on the audience screen at launch. This intentionally restores only what's selected; the operator presses play.
- **Graceful on deletion.** If the saved item/playlist was deleted between sessions, `resolve` returns `nil` rather than crashing — the app just opens with nothing selected.
