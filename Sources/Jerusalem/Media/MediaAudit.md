# `MediaAudit.swift`

> A pure namespace of functions that scan for missing media files on disk, so the slide grid can show a "missing file" badge *before* the missing file becomes a Sunday-morning surprise.

**Location:** `Sources/Jerusalem/Media/MediaAudit.swift`
**Role:** namespace (pure functions)

## What it does (plain English)

The renderer and video player both fail *safely* when a file is missing — they silently skip an image or fall back to black. That's great for reliability but terrible for *awareness*: the operator stress-testing on Saturday would have no idea a file went missing. `MediaAudit` exists to make that invisible-but-safe state visible.

It's a set of pure functions (no UI, no database) that check whether the files a slide depends on actually exist and are readable on disk. The slide grid uses the results to draw a "missing media" warning badge while there's still time to fix it.

There are three checks: one for a single filename, one that walks an entire `RenderableSlide` and returns every missing path, and a convenience one for a `VideoCue`.

## Swift you'll meet in this file

- `enum MediaAudit { static func ... }` — a caseless enum used as a namespace of pure static functions → `export const MediaAudit = { ... }`. No instances are ever made.
- `FileManager.default.isReadableFile(atPath:)` — the OS file-existence/readability check → `fs.accessSync(path, R_OK)`-style probe.
- `String?` optional + `guard let filename, !filename.isEmpty else { return false }` — early-return guard that unwraps and validates.
- `[String]` — an array (`string[]`); built up and returned.
- `for element in slide.elements where element.kind == .image` — a filtered loop (only image elements) → `for (const e of … ) if (e.kind === "image")`.
- `url.lastPathComponent` / `url.path` — the filename and the full filesystem path.
- `?.` optional chaining, `if let` binding.

## Code walkthrough

`isPresent(filename:)` is the single-file check. It rejects nil/empty names, resolves the on-disk URL via `MediaStorage`, and asks the OS if it's readable:

```swift
static func isPresent(filename: String?) -> Bool {
    guard let filename, !filename.isEmpty else { return false }
    let url = MediaStorage.url(forFilename: filename)
    return FileManager.default.isReadableFile(atPath: url.path)
}
```

**TypeScript equivalent**

```ts
// caseless enum ⇒ a namespace object of pure functions
const MediaAudit = {
  isPresent(filename: string | null): boolean {
    // guard let filename, !isEmpty else { return false }
    if (!filename) return false;        // covers null AND ""
    const url = MediaStorage.url(filename);
    return isReadableFile(url.path);
  },
};
```

**Swift syntax:**
- `enum MediaAudit { static func … }` — a *caseless* enum: no cases, never instantiated, purely a namespace for static helpers. Idiomatic Swift for "a module of pure functions" → a plain object / `export const`.
- `guard let filename, !filename.isEmpty else { return false }` — unwraps the optional (`let filename` is shorthand for `let filename = filename`) *and* checks it's non-empty; on failure returns `false`. After the guard, `filename` is a non-optional `String`.

`missingFiles(in:)` is the main workhorse — it walks every file path a `RenderableSlide` can carry and collects the ones that don't resolve:

```swift
static func missingFiles(in slide: RenderableSlide) -> [String] {
    var missing: [String] = []
    if let url = slide.backgroundImageURL,
       !FileManager.default.isReadableFile(atPath: url.path) {
        missing.append(url.lastPathComponent)
    }
    if let cue = slide.backgroundVideo,
       !FileManager.default.isReadableFile(atPath: cue.url.path) {
        missing.append(cue.url.lastPathComponent)
    }
    for element in slide.elements where element.kind == .image {
        if let filename = element.imageFilename, !isPresent(filename: filename) {
            missing.append(filename)
        }
    }
    return missing
}
```

**TypeScript equivalent**

```ts
missingFiles(slide: RenderableSlide): string[] {
  const missing: string[] = [];

  // background image: present-but-unreadable ⇒ record its filename
  const bgURL = slide.backgroundImageURL;
  if (bgURL && !isReadableFile(bgURL.path)) {
    missing.push(bgURL.lastPathComponent);
  }

  // background video
  const cue = slide.backgroundVideo;
  if (cue && !isReadableFile(cue.url.path)) {
    missing.push(cue.url.lastPathComponent);
  }

  // every image ELEMENT on the slide (filtered loop)
  for (const element of slide.elements) {
    if (element.kind !== "image") continue;     // `where element.kind == .image`
    const filename = element.imageFilename;
    if (filename && !MediaAudit.isPresent(filename)) {
      missing.push(filename);
    }
  }

  return missing;   // empty ⇒ slide is fully self-contained
}
```

**Swift syntax:**
- `var missing: [String] = []` — a mutable array (`let` would be immutable). `var` for accumulation → `const missing: string[] = []` (TS `const` binds the reference but the array is still mutable).
- `if let url = slide.backgroundImageURL, !isReadableFile(...) { … }` — combines an optional unwrap and a boolean test in one `if`: enters only when the URL exists *and* is unreadable → `if (url && !readable)`.
- `for element in slide.elements where element.kind == .image` — a `for`-loop with a `where` filter; iterations not matching the predicate are skipped → `for (…) { if (e.kind !== "image") continue; … }`.
- `url.lastPathComponent` — the final path segment (the filename) → `path.basename(url)`.

It checks three sources: the slide's background image, the slide's background video, and every image *element* on the slide. An empty array means the slide is fully self-contained (nothing missing). Note that the background image/video are checked by their resolved URL directly, while image elements go back through `isPresent(filename:)`.

`isPresent(_ cue:)` is the convenience for the live program's video items:

```swift
static func isPresent(_ cue: VideoCue) -> Bool {
    FileManager.default.isReadableFile(atPath: cue.url.path)
}
```

**TypeScript equivalent**

```ts
// overload by argument type ⇒ a separately-named/dispatched function in TS
isPresentCue(cue: VideoCue): boolean {
  return isReadableFile(cue.url.path);
}
```

**Swift syntax:**
- `static func isPresent(_ cue: VideoCue)` — Swift allows *overloading*: two functions both named `isPresent` distinguished by parameter type/label (`filename:` vs unlabeled `VideoCue`). TS lacks ad-hoc overloading by runtime type, so you'd give them distinct names or use a union + type guard.
- The body is a single expression with no `return` — single-expression functions implicitly return their one expression.

## How it connects

It depends on `MediaStorage.url(forFilename:)` to resolve names to on-disk paths, and it reads `RenderableSlide` / `VideoCue` value snapshots (the same value types the renderer and live path use). The slide grid / UI calls `missingFiles(in:)` per slide to decide whether to show the missing-media badge. It has no UI or model dependencies itself — it's pure, so it's directly unit-testable.

## Gotchas / why it matters

- **Safe ≠ visible.** The renderer's fallbacks (skip image / black video) keep the show running, but `MediaAudit` is what *surfaces* the problem during rehearsal — that's the whole reason it exists.
- **Pure by design** — caseless enum, no UI/model coupling, so it can be tested headlessly and reused anywhere.
- It mirrors exactly the paths the renderer/video player consult (background image, background video, image elements, video cues), so the audit matches reality.
- An empty `missingFiles(in:)` result is the all-clear signal for a slide.
