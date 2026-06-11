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
**Catches:** a case-sensitive or incomplete extension map that would reject a valid `.MOV` clip or accept an unsupported file type.

### `testImportFileCopiesIntoDirectory`
Creates a unique temp directory (cleaned up via `addTeardownBlock`), writes a tiny fake `clip.mp4`, then calls `MediaStorage.importFile(at:into:)`. Asserts the returned name ends in `.mp4` and that the file actually exists at the destination.
```swift
let name = try MediaStorage.importFile(at: source, into: destination)
XCTAssertTrue(name.hasSuffix(".mp4"))
XCTAssertTrue(FileManager.default.fileExists(
    atPath: destination.appendingPathComponent(name).path))
```
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
**Catches:** a video item not producing a video cue, or the loop flag being dropped (a welcome-loop that plays once and stops).

### `testVideoProgramGoesLiveAsVideoContent`
Arms a `.mov` media item and goes live (`next()`), then asserts `live.content` is the `.video` case with the cue url ending in `b.mov`.
**Catches:** a break between "video program slide" and "video actually showing on the output" — the going-live step losing the video.

### `testImageMediaBecomesImageSlide`
Builds a media item with `mediaFilename = "photo.png"` and checks `programSlides` yields one `.slide` whose `backgroundImageURL` ends in `photo.png` and whose `elements` array is empty (no text overlaid).
```swift
XCTAssertEqual(renderable.backgroundImageURL?.lastPathComponent, "photo.png")
XCTAssertTrue(renderable.elements.isEmpty)
```
**Catches:** an image being routed as video (or vice versa), or stray text elements appearing over a backdrop.

### `testUnknownMediaTypeProducesNoProgram`
A media item pointing at `notes.txt` yields an empty program.
**Catches:** an unsupported file slipping through and producing a broken program slide that would fail at playback time.

### `testPrewarmerCachesAssetByURL`
Asks `VideoPrewarmer` for `asset(for:)` twice with the same URL and asserts both calls return the **same instance** via `===`.
```swift
XCTAssertTrue(prewarmer.asset(for: url) === prewarmer.asset(for: url))
```
**Catches:** the pre-warmer re-loading the asset every call, defeating the whole point (low-latency start) and wasting memory.

### `testPrewarmIgnoresMissingAndNil`
Calls `prewarm(nil)` and `prewarm(...)` with a `VideoCue` for a non-existent file path. There's nothing to assert beyond "must not crash."
**Catches:** the pre-warmer throwing or crashing on a `nil` cue or a missing file — which would have to degrade to black, never to a crash, on Sunday.

## How it connects
Exercises `MediaImport.kind(forExtension:)`, `MediaStorage.importFile(at:into:)` (both pure/IO caseless-enum namespaces), `LiveState.programSlides` + `LiveState.arm`/`next`, the `ProgramSlide.kind` and `LiveState.Content` enums, `VideoCue`, `RenderableSlide`, and `VideoPrewarmer`. Models touched: `Item` (kind `.media`) and its `mediaFilename` / `videoLoops` fields.

## What it does NOT cover
Real AVFoundation playback. There is no actual decoding, looping smoothness, frame timing, or fallback-to-black-on-unplayable-file verification here — those need a real run, ideally on hardware with the output window. The tests only confirm the *routing and bookkeeping* (correct cue/url/flags, caching, no-crash on missing files).
