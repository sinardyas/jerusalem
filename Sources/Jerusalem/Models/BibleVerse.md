# `BibleVerse.swift`

> One database row representing a single Bible verse in a single translation (e.g. "John 3:16" in KJV).

**Location:** `Sources/Jerusalem/Models/BibleVerse.swift`
**Role:** SwiftData model (reference/seed content, read-only after import)

## What it does (plain English)
This is the storage shape for Bible text. Every verse, in every translation the app ships, becomes one `BibleVerse` row. Phase 7 ships two translations — KJV and WEB — and both live in the *same* table, distinguished by the `translation` field. So "John 3:16 KJV" and "John 3:16 WEB" are two separate rows.

It is **reference content, not user-authored**: the verses are seeded once at import time and then treated as read-only. The app looks them up to build slides; it never lets the operator edit the verse text.

The natural "primary key" is the combination `(translation, book, chapter, number)` — that four-part tuple uniquely identifies a verse. Storing this in SwiftData (rather than linking raw SQLite) lets the Bible reuse the same on-disk container, fetching, and ordering machinery as the rest of the app.

## Swift you'll meet in this file
- `@Model final class { … }` — a SwiftData database-backed class, like a Prisma/TypeORM entity. TS analog: `class BibleVerse { … }` with `// @Entity`. `final` (no subclassing) ≈ a class you wouldn't `extends`.
- `var foo: String = "..."` — `var` is a mutable property; `: String` is the type annotation; `= "..."` is a default value. TS: `foo: string = "..."`.
- `Int` / `String` — `number` (whole) / `string`.
- Computed property `var reference: String { ... }` — a getter with no `=`, just a `{ }` returning a value. TS: `get reference(): string { ... }`.
- `\(...)` inside a string — string interpolation. TS: `` `${...}` `` in a template literal.
- `init(...)` — the constructor. TS: `constructor(...)`.

## Code walkthrough

```swift
@Model
final class BibleVerse {
    var translation: String = "kjv"
    var book: String = ""
    var chapter: Int = 0
    var number: Int = 0
    var text: String = ""
```

**TypeScript equivalent**

```ts
// @Entity  (SwiftData @Model — one row per instance)
class BibleVerse {
  translation: string = "kjv";
  book: string = "";
  chapter: number = 0;
  number: number = 0;
  text: string = "";
}
```

**Swift syntax:**
- `@Model` — a macro that turns the class into a persisted SwiftData entity (each instance is a row). TS analog: an ORM `// @Entity` decorator.
- `final class` — a reference type that cannot be subclassed. TS: a `class` (the `final` is just "no `extends`").
- `var x: T = v` — mutable stored property with a default. The `: T` is the type; SwiftData wants defaults so it can create rows and evolve the schema.

`@Model` marks this as a SwiftData entity, so each instance is a row that can be saved, fetched, and queried. The five stored properties are the columns:

- `translation` — a lowercase tag like `"kjv"` or `"web"`. The doc comment notes this is deliberately a **free-form `String`, not an `enum`**, so adding a new translation (ASV, BBE, …) later doesn't force a database migration.
- `book` — the canonical book name, e.g. `"John"`, `"1 Corinthians"`, `"Psalms"`. A parser normalizes user input to this canonical form before insert.
- `chapter`, `number` — the chapter and verse numbers (`Int`).
- `text` — the actual verse text.

Each property has a default value (`"kjv"`, `""`, `0`). SwiftData generally wants defaults so it can create rows and evolve the schema cleanly.

```swift
init(translation: String, book: String, chapter: Int, number: Int, text: String) {
    self.translation = translation
    self.book = book
    self.chapter = chapter
    self.number = number
    self.text = text
}
```

**TypeScript equivalent**

```ts
constructor(translation: string, book: string, chapter: number, number: number, text: string) {
  this.translation = translation;
  this.book = book;
  this.chapter = chapter;
  this.number = number;
  this.text = text;
}
```

**Swift syntax:**
- `init(...)` — the constructor; called as `BibleVerse(translation: ..., book: ...)`. Note the **argument labels**: callers must name each argument (`translation:`), unlike a positional TS call.
- `self.x = x` — assigning the parameter to the property. TS: `this.x = x`.

The constructor just assigns each argument to the matching property. `self.x = x` is the same as JS `this.x = x`.

```swift
var reference: String { "\(book) \(chapter):\(number)" }
```

**TypeScript equivalent**

```ts
get reference(): string {
  return `${this.book} ${this.chapter}:${this.number}`;
}
```

**Swift syntax:**
- `var x: T { ... }` (no `=`, no `get`/`set` keyword) — a read-only **computed property**; the `{ }` block's value is returned. TS: `get x(): T { return ... }`.
- A single-expression `{ }` body has an implicit return — no `return` keyword needed.

This is a **computed property** (a getter — note there's no `=`, just a `{ }` block returning a value). It builds the human-facing label like `"John 3:16"` from the stored fields. The `"\(book) \(chapter):\(number)"` is string interpolation: it reads like `` `${book} ${chapter}:${number}` `` in JS. This label is shown to the operator as the slide's section label so they always know exactly what's being projected.

## How it connects
`BibleVerse` is mostly standalone — it has no relationships to `Item`, `Slide`, etc. It's a lookup table. When the user references a passage, other code (a reference parser plus a verse splitter) queries these rows by `(translation, book, chapter, number)` and *materializes* the verse text into `Slide`/`SlideElement` rows on an `Item`. The Bible rows themselves stay untouched.

## Gotchas / why it matters
- **Composite uniqueness.** The comment mentions `@Attribute(.unique)` enforcing the natural composite key, though in this version of the file the explicit attribute isn't present on the properties — the doc describes the intended invariant: a verse is uniquely `(translation, book, chapter, number)`. Don't create duplicate rows for the same verse/translation.
- **Read-only by convention.** Nothing stops you from mutating these rows at runtime, but the design treats them as immutable seed data. Editing happens on derived `Slide`/`SlideElement` rows, never here.
- **Same table, many translations.** Always filter by `translation` when querying, or you'll mix KJV and WEB results.
