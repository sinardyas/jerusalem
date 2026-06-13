# `MediaTests.swift`

> Verifies the media pipeline: file-extension type rules, copying imports onto disk, and turning a media `Item` into the right kind of program slide (looping video, image background, or nothing for unknown types) — plus the video pre-warmer's caching.

**Location:** `Tests/JerusalemTests/MediaTests.swift`
**Role:** XCTest unit tests (Phase 5, part 1)

## What it does (plain English)
Phase 5 adds video and image media. This file guards the decidable, headless rules around it: which file extensions count as video vs image, that importing a file actually copies it into the media directory under a safe name, and that a media `Item` resolves to the correct live-output shape — a `VideoCue` for clips (carrying its loop flag and url), a background-image slide for pictures, and *nothing* for unsupported files like `.txt`.

It also touches `VideoPrewarmer`, the pre-buffering singleton that reduces video start latency. The tests confirm it caches the underlying asset per URL (so the same clip isn't re-loaded) and that asking it to pre-warm a missing file or `nil` simply does nothing instead of crashing — important because a missing clip must degrade to black, never take down the output.

This is the programmatic slice. Whether the video actually plays back smoothly through AVFoundation is a hardware/runtime concern verified by hand.

## XCTest you'll meet in this file
- `final class MediaTests: XCTestCase` — the suite.
- `func test...() throws` — a test that may throw; a thrown error fails it.
- `@MainActor` — main-thread tests (the ones touching `LiveState` / `VideoPrewarmer`).
- `XCTAssertEqual` / `XCTAssertNil` / `XCTAssertTrue` — `expect(...)` equivalents.
- `XCTFail(...)` inside `guard case` — fail if the enum pattern doesn't match.
- `addTeardownBlock { ... }` — registers cleanup to run after the test, like a per-test `afterEach`/`finally`; used to delete the temp directory.
- `===` — *identity* comparison (same object reference), like JS `===` on objects. Used to prove the pre-warmer returns the *same cached* asset instance.
- `guard case .video(let cue) = ... else { return XCTFail(...) }` — tagged-union pattern match binding the `.video` payload.

## The tests, one by one

### `testMediaKindByExtension`
Table test for `MediaImport.kind(forExtension:)`: `mp4`, `MOV`, `m4v` → `.video`; `png`, `JPG` → `.image`; `txt` → `nil`. Note the mixed casing — extensions are matched case-insensitively.
```swift
XCTAssertEqual(MediaImport.kind(forExtension: "MOV"), .video)
XCTAssertNil(MediaImport.kind(forExtension: "txt"))
```

**TypeScript equivalent (Jest)**

```ts
// analogy: Swift enum case `.video` ≈ a "video" tag / string literal.
expect(MediaImport.kind("MOV")).toEqual("video");
expect(MediaImport.kind("txt")).toBeNull();
```

**Swift syntax:**
- `final class MediaTests: XCTestCase` — shape: subclass = test suite. Jest: `describe("MediaTests", () => { … })`.
- `MediaImport.kind(forExtension: "MOV")` — shape: `forExtension:` is the argument label (full method name `kind(forExtension:)`). Jest: positional `kind("MOV")`.
- `XCTAssertEqual(x, .video)` — shape: leading-dot `.video` lets Swift infer the enum type from context. Jest: compare against `"video"`.

**Catches:** a case-sensitive or incomplete extension map that would reject a valid `.MOV` clip or accept an unsupported file type.

### `testImportFileCopiesIntoDirectory`
Creates a unique temp directory (cleaned up via `addTeardownBlock`), writes a tiny fake `clip.mp4`, then calls `MediaStorage.importFile(at:into:)`. Asserts the returned name ends in `.mp4` and that the file actually exists at the destination.
```swift
let name = try MediaStorage.importFile(at: source, into: destination)
XCTAssertTrue(name.hasSuffix(".mp4"))
XCTAssertTrue(FileManager.default.fileExists(
    atPath: destination.appendingPathComponent(name).path))
```

**TypeScript equivalent (Jest)**

```ts
// analogy: addTeardownBlock(...) ≈ afterEach(...) cleanup, registered inline.
const root = path.join(os.tmpdir(), `jx-${randomUUID()}`);
afterEach(() => fs.rmSync(root, { recursive: true, force: true }));
fs.mkdirSync(root, { recursive: true });
const source = path.join(root, "clip.mp4");
fs.writeFileSync(source, Buffer.from([0, 1, 2, 3]));
const destination = path.join(root, "media");

const name = MediaStorage.importFile(source, destination);
expect(name.endsWith(".mp4")).toBe(true);                       // .hasSuffix(".mp4")
expect(fs.existsSync(path.join(destination, name))).toBe(true); // fileExists(atPath:)
```

**Swift syntax:**
- `func testImportFileCopiesIntoDirectory() throws` — shape: a `throws` test; the `try` calls inside can fail it. Jest: an `async`/throwing `it`.
- `addTeardownBlock { try? FileManager.default.removeItem(at: root) }` — shape: registers a *teardown closure* to run after the test (trailing-closure syntax — the `{ … }` is the last argument). Jest: `afterEach(() => …)` registered inline.
- `let name = try MediaStorage.importFile(at: source, into: destination)` — shape: `try` prefixes a throwing call; `at:`/`into:` are argument labels. Jest: `const name = MediaStorage.importFile(source, destination)`.
- `name.hasSuffix(".mp4")` — shape: string suffix check. Jest: `name.endsWith(".mp4")`.

**Catches:** import silently failing to copy the file, or losing the file extension — which would break playback later because the media would be missing or mis-typed on disk.

### `testMediaItemBecomesVideoProgramSlide`
Builds a `media` `Item` with `mediaFilename = "abc.mp4"` and `videoLoops = true`, then checks `LiveState.programSlides(for:)` yields exactly one slide whose kind is `.video`, with `cue.loops == true` and the cue's url ending in `abc.mp4`.
```swift
guard case .video(let cue) = program[0].kind else {
    return XCTFail("expected a video program slide")
}
XCTAssertTrue(cue.loops)
XCTAssertEqual(cue.url.lastPathComponent, "abc.mp4")
```

**TypeScript equivalent (Jest)**

```ts
// analogy: `guard case .video(let cue)` ≈ narrowing a discriminated union by its tag.
if (program[0].kind.type !== "video") {
  throw new Error("expected a video program slide"); // XCTFail
}
const cue = program[0].kind.cue;
expect(cue.loops).toBe(true);
expect(cue.url.lastPathComponent).toEqual("abc.mp4");
```

**Swift syntax:**
- `guard case .video(let cue) = program[0].kind else { return XCTFail("…") }` — shape: match the `.video` enum case and bind its associated `VideoCue` to `cue`, else fail. Jest: narrow a union by `type`, else `throw`.

**Catches:** a video item not producing a video cue, or the loop flag being dropped (a welcome-loop that plays once and stops).

### `testVideoProgramGoesLiveAsVideoContent`
Arms a `.mov` media item and goes live (`next()`), then asserts `live.content` is the `.video` case with the cue url ending in `b.mov`.

```swift
live.arm(LiveState.programSlides(for: item))
live.next()
guard case .video(let cue) = live.content else {
    return XCTFail("expected video content")
}
XCTAssertEqual(cue.url.lastPathComponent, "b.mov")
```

**TypeScript equivalent (Jest)**

```ts
live.arm(LiveState.programSlides(item));
live.next();
if (live.content.type !== "video") {
  throw new Error("expected video content"); // XCTFail
}
const cue = live.content.cue;
expect(cue.url.lastPathComponent).toEqual("b.mov");
```

**Catches:** a break between "video program slide" and "video actually showing on the output" — the going-live step losing the video.

### `testImageMediaBecomesImageSlide`
Builds a media item with `mediaFilename = "photo.png"` and checks `programSlides` yields one `.slide` whose `backgroundImageURL` ends in `photo.png` and whose `elements` array is empty (no text overlaid).
```swift
XCTAssertEqual(renderable.backgroundImageURL?.lastPathComponent, "photo.png")
XCTAssertTrue(renderable.elements.isEmpty)
```

**TypeScript equivalent (Jest)**

```ts
// analogy: Swift `?.` optional chaining is the same `?.` in TS.
expect(renderable.backgroundImageURL?.lastPathComponent).toEqual("photo.png");
expect(renderable.elements.length).toBe(0); // .isEmpty
```

**Swift syntax:**
- `renderable.backgroundImageURL?.lastPathComponent` — shape: `backgroundImageURL` is an optional `URL`, so `?.` reads its `lastPathComponent` or yields `nil`. Jest: identical `?.`.

**Catches:** an image being routed as video (or vice versa), or stray text elements appearing over a backdrop.

### `testUnknownMediaTypeProducesNoProgram`
A media item pointing at `notes.txt` yields an empty program.

```swift
item.mediaFilename = "notes.txt"
XCTAssertTrue(LiveState.programSlides(for: item).isEmpty)
```

**TypeScript equivalent (Jest)**

```ts
item.mediaFilename = "notes.txt";
expect(LiveState.programSlides(item).length).toBe(0); // .isEmpty
```

**Catches:** an unsupported file slipping through and producing a broken program slide that would fail at playback time.

### `testPrewarmerCachesAssetByURL`
Asks `VideoPrewarmer` for `asset(for:)` twice with the same URL and asserts both calls return the **same instance** via `===`.
```swift
XCTAssertTrue(prewarmer.asset(for: url) === prewarmer.asset(for: url))
```

**TypeScript equivalent (Jest)**

```ts
// analogy: Swift `===` (reference identity) ≈ JS `===` / Object.is on objects.
expect(prewarmer.asset(url) === prewarmer.asset(url)).toBe(true);
// or, idiomatically: expect(prewarmer.asset(url)).toBe(prewarmer.asset(url));
```

**Swift syntax:**
- `a === b` — shape: *identity* comparison — true only when both refer to the same object instance (distinct from `==`, which compares values). Jest: `===`/`Object.is` on objects, or `expect(a).toBe(b)` (which uses `Object.is`).

**Catches:** the pre-warmer re-loading the asset every call, defeating the whole point (low-latency start) and wasting memory.

### `testPrewarmIgnoresMissingAndNil`
Calls `prewarm(nil)` and `prewarm(...)` with a `VideoCue` for a non-existent file path. There's nothing to assert beyond "must not crash."

```swift
prewarmer.prewarm(nil)
prewarmer.prewarm(VideoCue(url: URL(fileURLWithPath: "/does/not/exist.mov"),
                           loops: false, muted: true, endBehavior: .hold))
// Must not crash; nothing else to assert.
```

**TypeScript equivalent (Jest)**

```ts
// analogy: passing `nil` ≈ passing `null`; the "test" is simply that it doesn't throw.
expect(() => {
  prewarmer.prewarm(null);
  prewarmer.prewarm(new VideoCue({
    url: { fileURLWithPath: "/does/not/exist.mov" },
    loops: false, muted: true, endBehavior: "hold",
  }));
}).not.toThrow();
```

**Swift syntax:**
- `prewarm(nil)` — shape: `nil` passed where an `Optional` is expected. Jest: `null`.
- `VideoCue(url: …, loops: false, muted: true, endBehavior: .hold)` — shape: a struct's memberwise initializer; `endBehavior: .hold` uses leading-dot enum inference. Jest: an object/constructor with a `"hold"` tag.
- (No explicit assert) — shape: the test passes simply by not crashing. Jest: wrap in `expect(() => …).not.toThrow()` to make that intent explicit.

**Catches:** the pre-warmer throwing or crashing on a `nil` cue or a missing file — which would have to degrade to black, never to a crash, on Sunday.

## How it connects
Exercises `MediaImport.kind(forExtension:)`, `MediaStorage.importFile(at:into:)` (both pure/IO caseless-enum namespaces), `LiveState.programSlides` + `LiveState.arm`/`next`, the `ProgramSlide.kind` and `LiveState.Content` enums, `VideoCue`, `RenderableSlide`, and `VideoPrewarmer`. Models touched: `Item` (kind `.media`) and its `mediaFilename` / `videoLoops` fields.

## What it does NOT cover
Real AVFoundation playback. There is no actual decoding, looping smoothness, frame timing, or fallback-to-black-on-unplayable-file verification here — those need a real run, ideally on hardware with the output window. The tests only confirm the *routing and bookkeeping* (correct cue/url/flags, caching, no-crash on missing files).

## XCTest → Jest glossary
- `final class X: XCTestCase { }` — shape: subclass = test suite. Jest: `describe("X", () => { … })`.
- `func testFoo() throws` — shape: `test`-prefixed, may throw → can fail. Jest: `it("foo", async () => { … })`.
- `@MainActor` — shape: main-thread run (for `LiveState`/`VideoPrewarmer`). Jest: `// runs on the main thread`.
- `XCTAssertEqual(a, b)` — Jest: `expect(a).toEqual(b)`.
- `XCTAssertNil(x)` — Jest: `expect(x).toBeNull()`.
- `XCTAssertTrue(x)` — Jest: `expect(x).toBe(true)`.
- `XCTFail("m")` — shape: unconditional failure. Jest: `throw new Error("m")`.
- `addTeardownBlock { … }` — shape: register post-test cleanup (trailing-closure). Jest: `afterEach(() => …)`.
- `guard case .video(let cue) = value else { … }` — shape: match an enum case + bind its payload, else exit. Jest: narrow a discriminated union by `type`, else `throw`.
- `===` — shape: reference identity. Jest: `===`/`Object.is` (or `expect(a).toBe(b)`).
- `?.` — shape: optional chaining. Jest: `?.`.
- `.isEmpty` / `.hasSuffix(...)` — shape: emptiness / suffix string checks. Jest: `.length === 0` / `.endsWith(...)`.
- `enum` + leading-dot case (`.video(...)`, `.image`, `.hold`) — shape: tagged union, possibly with payload. Jest: `{ type: "video", cue }` / `"image"` / `"hold"`.
