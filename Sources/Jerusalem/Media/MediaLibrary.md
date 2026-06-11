# `MediaLibrary.swift`

> Two pure namespaces: `MediaImport` decides whether a file is a video or image by extension, and `MediaStorage` manages copying imported media into the app's on-disk media folder.

**Location:** `Sources/Jerusalem/Media/MediaLibrary.swift`
**Role:** namespace (pure rules + on-disk storage)

## What it does (plain English)

When the operator drops in a video or image, two questions arise: "what kind of file is this?" and "where do we keep it?" This file answers both with small, pure helpers.

`MediaImport` holds the file-type rules — the allowed video and image extensions, and a function that maps an extension to a `MediaKind` (or `nil` for unsupported types). It's just data and a lookup, so it's trivially testable.

`MediaStorage` owns the on-disk location: everything lives under `Application Support/Jerusalem/Media`. It can give you that directory (creating it if needed), turn a stored filename into a full URL, and import a source file by copying it in under a fresh unique name. Renaming to a UUID avoids collisions when two files share a name.

## Swift you'll meet in this file

- `enum MediaKind: Equatable { case video, image }` — a simple TS-style union (no associated data).
- `enum MediaImport { static let ... }` and `enum MediaStorage { static ... }` — caseless enums as namespaces of constants/functions (`export const MediaImport = { ... }`).
- `Set<String>` — a set (`Set<string>`); used for fast `.contains` extension lookups.
- `URL` — a file URL; `.appendingPathComponent(...)`, `.pathExtension`, `.path` build/inspect paths.
- `FileManager.default` — the OS filesystem API.
- `try` / `throws` — Swift error handling; `try?` swallows to `nil`, `try` propagates.
- `@discardableResult` — callers may ignore the returned value without a warning.
- `MediaKind?` optional return; `?? self.directory` nullish default.
- `.first!` force-unwrap (crashes if nil) and `UUID().uuidString` for unique names.

## Code walkthrough

`MediaKind` is the two-case result type. `MediaImport` is the rule set:

```swift
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

The `.first!` force-unwrap assumes the Application Support directory always exists (it does on macOS). The `try?` means a creation failure is silently ignored — the directory almost always already exists after first use.

`url(forFilename:)` just joins a stored filename onto that directory. `importFile(at:into:)` does the actual copy:

```swift
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

It defaults to the media directory (but accepts an override, which is handy for tests), ensures the directory exists, generates a `UUID`-based filename keeping the original extension, copies the file in, and returns the new stored filename. Copy failures `throw` (caller handles). The `into:` parameter defaulting to `nil` is the idiomatic Swift way of making the directory injectable for unit tests.

## How it connects

`MediaImport.kind(forExtension:)` is used by `LiveState.programSlides(for:)` to route a media item to video vs. image. `MediaStorage.url(forFilename:)` is the single resolver from a stored filename to an on-disk URL — used by `LiveState` (building cues/slides), `MediaAudit` (checking presence), and the renderer. `importFile(...)` is what the import UI calls when the operator adds media; the returned filename is what gets stored on the `Item` model.

## Gotchas / why it matters

- **One canonical location.** All imported media lives under `Application Support/Jerusalem/Media`, and `url(forFilename:)` is the one way to resolve a name to a path — so audits, rendering, and import all agree on where files are.
- **UUID renaming** prevents filename collisions and keeps the extension so type detection still works.
- **Pure rules, injectable storage** — `MediaImport` is pure data/logic; `MediaStorage.importFile` takes an optional directory so it's testable without touching the real Application Support folder.
- The supported-extensions sets are the single source of truth for "what can be imported" — extend them here, not scattered around.
