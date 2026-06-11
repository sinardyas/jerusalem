# `VideoPrewarmer.swift`

> A global singleton that pre-loads the *next* video clip's asset (bounded LRU cache) so playback starts quickly when the operator switches to it.

**Location:** `Sources/Jerusalem/Live/VideoPrewarmer.swift`
**Role:** singleton

## What it does (plain English)

Starting a video from cold means AVFoundation has to open the file and buffer the first frames, which adds a visible delay. `VideoPrewarmer` reduces that delay by loading the *upcoming* clip's asset ahead of time, in the background, so by the time it actually goes on screen it's already partly buffered.

It's a single global instance (`VideoPrewarmer.shared`) holding a small cache of `AVURLAsset`s keyed by file URL. The cache is bounded to 4 entries with a simple least-recently-added eviction, so it never grows unboundedly. The key trick: the *same* asset instance handed out for prewarming is the one the live player later reuses — so any buffering already done isn't wasted.

It's explicitly best-effort. The doc comment is honest that this isn't a guarantee of instant start; the real-world benefit must be measured on hardware.

## Swift you'll meet in this file

- `@MainActor final class` with `static let shared` — a singleton (one global instance), pinned to the main/UI thread.
- `AVURLAsset` — AVFoundation's representation of a media file, which can load metadata/buffers asynchronously.
- `[URL: AVURLAsset]` — a dictionary (`Map<URL, AVURLAsset>`); `[URL]` is an array used to track insertion order.
- `Task { ... }` — fire-and-forget async work (same idea as in JS).
- `await asset.load(.isPlayable, .duration)` — async load of the asset's properties; `try?` swallows errors into `nil`.
- `T?`, `if let existing = ...` (bind-or-skip), `guard ... else { return }` early exit.
- `_ = ...` — explicitly discard a result.

## Code walkthrough

The singleton holds a URL→asset cache, an insertion-order list, and a hard limit:

```swift
@MainActor
final class VideoPrewarmer {
    static let shared = VideoPrewarmer()

    private var assets: [URL: AVURLAsset] = [:]
    private var order: [URL] = []
    private let limit = 4
```

`asset(for:)` is the shared accessor used by both prewarming *and* the live player:

```swift
func asset(for url: URL) -> AVURLAsset {
    if let existing = assets[url] { return existing }
    let asset = AVURLAsset(url: url)
    store(asset, for: url)
    Task { _ = try? await asset.load(.isPlayable, .duration) }
    return asset
}
```

On a cache hit it returns the existing asset (so buffering is reused). On a miss it creates the asset, caches it, and kicks off an async load of `.isPlayable` and `.duration` in a fire-and-forget `Task` — that async load is what warms the buffers. The errors are swallowed with `try?` because a failed prewarm should never throw; the live `VideoPlayerView` will handle a bad file by showing black anyway.

`prewarm(_:)` is what the live code calls to warm the *next* clip:

```swift
func prewarm(_ cue: VideoCue?) {
    guard let cue, !cue.loops, FileManager.default.fileExists(atPath: cue.url.path) else { return }
    _ = asset(for: cue.url)
}
```

It only warms non-looping clips that actually exist on disk — a loop "starts once and stays," so there's nothing to pre-warm, and a missing file is skipped. It just calls `asset(for:)` and discards the return value (the side effect — caching + async load — is the point).

`store(_:for:)` maintains the bounded LRU:

```swift
private func store(_ asset: AVURLAsset, for url: URL) {
    assets[url] = asset
    order.append(url)
    while order.count > limit {
        assets[order.removeFirst()] = nil
    }
}
```

It records the asset and its URL, then evicts the oldest entries until the cache is back at or under `limit` (4).

## How it connects

`VideoPlayerView.apply(_:)` calls `VideoPrewarmer.shared.asset(for: cue.url)` to build its `AVPlayerItem`, so it transparently reuses any prewarmed/buffered asset. Whoever drives the program (the operator/live layer, knowing the *next* `ProgramSlide`'s `videoCue`) calls `prewarm(_:)` ahead of time to warm the upcoming clip. The cache is shared across both paths via the single `shared` instance.

## Gotchas / why it matters

- **Same instance reuse is the whole optimization.** Because `asset(for:)` returns the cached `AVURLAsset`, the live player inherits any buffering the prewarm already did. Two separate assets for the same file would defeat the purpose.
- **Best-effort, not a promise.** The comment is explicit — this lowers latency but doesn't guarantee instant start; verify on hardware.
- **Bounded cache** (limit 4) keeps memory in check during a long service.
- **Loops aren't prewarmed** — they start once and persist, so there's nothing to gain.
- **`@MainActor` singleton** keeps cache access serialized on the UI thread, avoiding data races.
