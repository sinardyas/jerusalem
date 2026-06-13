# `MediaLibrary.swift`

> Two pure namespaces: `MediaImport` decides whether a file is a video or image by extension, and `MediaStorage` manages copying imported media into the app's on-disk media folder.

**Location:** `Sources/Jerusalem/Media/MediaLibrary.swift`
**Role:** namespace (pure rules + on-disk storage)

## What it does (plain English)

When the operator drops in a video or image, two questions arise: "what kind of file is this?" and "where do we keep it?" This file answers both with small, pure helpers.

`MediaImport` holds the file-type rules — the allowed video and image extensions, and a function that maps an extension to a `MediaKind` (or `nil` for unsupported types). It's just data and a lookup, so it's trivially testable.

`MediaStorage` owns the on-disk location: everything lives under `Application Support/Jerusalem/Media`. It can give you that directory (creating it if needed), turn a stored filename into a full URL, and import a source file by copying it in under a fresh unique name. Renaming to a UUID avoids collisions when two files share a name.

## Swift you'll meet in this file

- `enum MediaKind: Equatable { case video, image }` — a simple TS-style union (no associated data) → `type MediaKind = "video" | "image"`.
- `enum MediaImport { static let ... }` and `enum MediaStorage { static ... }` — caseless enums as namespaces of constants/functions → `export const MediaImport = { ... }`.
- `Set<String>` — a set (`Set<string>`); used for fast `.contains` extension lookups.
- `URL` — a file URL; `.appendingPathComponent(...)`, `.pathExtension`, `.path` build/inspect paths.
- `FileManager.default` — the OS filesystem API → Node's `fs`.
- `try` / `throws` — Swift error handling; `try?` swallows to `nil`, `try` propagates → `throw` + `try/catch`.
- `@discardableResult` — callers may ignore the returned value without a warning.
- `MediaKind?` optional return; `?? self.directory` nullish default.
- `.first!` force-unwrap (crashes if nil) and `UUID().uuidString` for unique names.

## Code walkthrough

`MediaKind` is the two-case result type. `MediaImport` is the rule set:

```swift
enum MediaKind: Equatable { case video, image }

enum MediaImport {
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "gif"]

    static func kind(forExtension ext: String) -> MediaKind? {
        let lowered = ext.lowercased()
        if videoExtensions.contains(lowered) { return .video }
        if imageExtensions.contains(lowered) { return .image }
        return nil
    }
}
```

**TypeScript equivalent**

```ts
type MediaKind = "video" | "image";   // enum with no associated data ⇒ string union

// caseless enum ⇒ a namespace of constants + a pure lookup
const MediaImport = {
  videoExtensions: new Set(["mp4", "mov", "m4v"]),
  imageExtensions: new Set(["png", "jpg", "jpeg", "heic", "tiff", "gif"]),

  kind(ext: string): MediaKind | null {   // MediaKind? ⇒ MediaKind | null
    const lowered = ext.toLowerCase();
    if (this.videoExtensions.has(lowered)) return "video";
    if (this.imageExtensions.has(lowered)) return "image";
    return null;                          // unsupported type
  },
};
```

**Swift syntax:**
- `enum MediaKind: Equatable { case video, image }` — a plain enum (no payloads) with auto value-equality → a string union.
- `static let videoExtensions: Set<String> = [...]` — a type-level constant; `Set` is built from an array literal and gives O(1) `.contains` → `new Set([...])`.
- `static func kind(forExtension ext: String)` — `forExtension` is the external argument label (call site: `kind(forExtension: "mp4")`), `ext` the internal name. → a single param in TS.

`kind(forExtension:)` lowercases the extension and returns `.video`, `.image`, or `nil` (unsupported). This is the function `LiveState.programSlides(for:)` calls to decide whether a media item becomes a `VideoCue` or an image-backed slide.

`MediaStorage` manages the directory. `directory` lazily creates `Application Support/Jerusalem/Media` and returns it:

```swift
static var directory: URL {
    let base = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        .appendingPathComponent("Jerusalem/Media", isDirectory: true)
    try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    return base
}
```

**TypeScript equivalent**

```ts
const MediaStorage = {
  get directory(): URL {
    const base = FileManager.default
      .urls("applicationSupportDirectory", "userDomainMask")[0]   // .first! (force)
      .appendingPathComponent("Jerusalem/Media", { isDirectory: true });
    // try? ⇒ attempt, ignore any error (dir almost always already exists)
    try { FileManager.default.createDirectory(base, { intermediates: true }); }
    catch { /* ignore */ }
    return base;
  },
};
```

**Swift syntax:**
- `static var directory: URL { … }` — a *computed* type-level property (a getter, recomputed each access), not a stored constant. → a static `get directory()`.
- `.first!` — `first` returns an optional (the array could be empty); `!` *force-unwraps* it, crashing if `nil`. Safe here because Application Support always exists on macOS. → `arr[0]` (but with an assert-it-exists contract).
- `try? FileManager.default.createDirectory(...)` — `try?` runs a throwing call and turns any error into `nil` (discarding it). The directory creation is best-effort. → `try { … } catch {}`.
- `.appendingPathComponent("Jerusalem/Media", isDirectory: true)` — builds a child URL; `isDirectory: true` hints it's a folder → `path.join(...)`.

The `.first!` force-unwrap assumes the Application Support directory always exists (it does on macOS). The `try?` means a creation failure is silently ignored — the directory almost always already exists after first use.

`url(forFilename:)` just joins a stored filename onto that directory. `importFile(at:into:)` does the actual copy:

```swift
static func url(forFilename name: String) -> URL {
    directory.appendingPathComponent(name)
}

@discardableResult
static func importFile(at source: URL, into dir: URL? = nil) throws -> String {
    let directory = dir ?? self.directory
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let ext = source.pathExtension
    let name = UUID().uuidString + (ext.isEmpty ? "" : ".\(ext)")
    try FileManager.default.copyItem(at: source, to: directory.appendingPathComponent(name))
    return name
}
```

**TypeScript equivalent**

```ts
// the single name→path resolver
url(name: string): URL {
  return MediaStorage.directory.appendingPathComponent(name);
},

// @discardableResult ⇒ callers may ignore the return without a warning.
// `throws` ⇒ the function can throw; the caller must try/catch (or rethrow).
importFile(source: URL, dir: URL | null = null): string {  // into: defaults to null
  const directory = dir ?? MediaStorage.directory;          // ?? nullish default
  FileManager.default.createDirectory(directory, { intermediates: true }); // may throw
  const ext = source.pathExtension;
  // UUID rename keeps the extension so type detection still works
  const name = crypto.randomUUID() + (ext === "" ? "" : `.${ext}`);  // string interp
  FileManager.default.copyItem(source, directory.appendingPathComponent(name)); // may throw
  return name;   // the new stored filename
},
```

**Swift syntax:**
- `@discardableResult` — suppresses the "result of call is unused" warning, so a caller can invoke `importFile(...)` purely for its side effect → no TS analog (TS never warns on ignored returns).
- `throws` / `try` — `throws` marks the function as error-throwing; each call inside that can fail is prefixed with `try` (no swallowing — the error propagates to the caller). Unlike `try?`, a bare `try` rethrows. → `throw` + the caller's `try/catch`.
- `into dir: URL? = nil` — an optional parameter with a default of `nil`; callers can omit it. The idiomatic way to make the directory injectable for tests. → `dir: URL | null = null`.
- `dir ?? self.directory` — nil-coalescing: use the passed directory, else fall back to the default → `dir ?? MediaStorage.directory`.
- `UUID().uuidString + (ext.isEmpty ? "" : ".\(ext)")` — `UUID()` makes a fresh unique id; `.\(ext)` is *string interpolation* (`\(expr)` injects a value into a string literal) → template literal `` `.${ext}` ``.

It defaults to the media directory (but accepts an override, which is handy for tests), ensures the directory exists, generates a `UUID`-based filename keeping the original extension, copies the file in, and returns the new stored filename. Copy failures `throw` (caller handles). The `into:` parameter defaulting to `nil` is the idiomatic Swift way of making the directory injectable for unit tests.

## How it connects

`MediaImport.kind(forExtension:)` is used by `LiveState.programSlides(for:)` to route a media item to video vs. image. `MediaStorage.url(forFilename:)` is the single resolver from a stored filename to an on-disk URL — used by `LiveState` (building cues/slides), `MediaAudit` (checking presence), and the renderer. `importFile(...)` is what the import UI calls when the operator adds media; the returned filename is what gets stored on the `Item` model.

## Gotchas / why it matters

- **One canonical location.** All imported media lives under `Application Support/Jerusalem/Media`, and `url(forFilename:)` is the one way to resolve a name to a path — so audits, rendering, and import all agree on where files are.
- **UUID renaming** prevents filename collisions and keeps the extension so type detection still works.
- **Pure rules, injectable storage** — `MediaImport` is pure data/logic; `MediaStorage.importFile` takes an optional directory so it's testable without touching the real Application Support folder.
- The supported-extensions sets are the single source of truth for "what can be imported" — extend them here, not scattered around.
