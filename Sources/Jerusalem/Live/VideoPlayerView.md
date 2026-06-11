# `VideoPlayerView.swift`

> A SwiftUI wrapper around AVFoundation video playback for the audience output — hardware-decoded, looping or one-shot, and engineered to fall back to black rather than ever crash.

**Location:** `Sources/Jerusalem/Live/VideoPlayerView.swift`
**Role:** NSViewRepresentable (+ its backing AppKit view)

## What it does (plain English)

SwiftUI has no good native way to play a video onto a layer with precise control, so this file drops down to AppKit and AVFoundation. `VideoPlayerView` is the thin SwiftUI shell; the real work is in `PlayerContainerView`, a hand-written AppKit `NSView` that hosts an `AVPlayerLayer` (the surface that shows decoded frames).

Given a `VideoCue` (a value snapshot describing a clip), it builds the right kind of player. For looping clips it uses `AVQueuePlayer` + `AVPlayerLooper` (seamless loops). For one-shot clips it uses a plain `AVPlayer` and listens for the "played to end" event to fire its `onEnded` callback. It hardware-decodes via the GPU and letterboxes (aspect-fit), so the black output shows through around the edges.

The safety story is everything: if the file is missing or unplayable, it shows nothing (black) instead of throwing. Video must never take down the live output.

## Swift you'll meet in this file

- `NSViewRepresentable` — a SwiftUI protocol for wrapping an AppKit `NSView` so it can be used like a SwiftUI view (like wrapping a non-React widget in a React component). You implement `makeNSView` (create), `updateNSView` (sync props), and optionally `dismantleNSView` (cleanup on removal).
- `NSView` — a UI box in the old AppKit layer.
- `CALayer` / layer-backed view (`wantsLayer = true`) — the Core Animation layer that actually draws.
- `AVPlayerLayer` — the layer that displays video frames.
- `AVPlayer` / `AVQueuePlayer` / `AVPlayerItem` / `AVPlayerLooper` — AVFoundation's playback engine pieces.
- `NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, ...)` — subscribing to the "clip finished" OS event.
- `[weak self]` — a non-retaining capture inside the closure, to avoid a retain cycle (memory leak) between the observer and the view.
- `MainActor.assumeIsolated { ... }` — "I know this callback already runs on the main thread, treat it as such" (lets main-actor code run without an await).
- `@available(*, unavailable)` — marks the `init(coder:)` initializer as forbidden.
- `final class`, `var`, optionals (`AVPlayer?`), `guard ... else { return }` early exits.
- Closures `{ ... }` = arrow functions; `onEnded: () -> Void = {}` is a callback prop with a default no-op.

## Code walkthrough

`VideoPlayerView` is the SwiftUI bridge. It just forwards the cue and callback into the AppKit view at create-and-update time, and tears the player down when SwiftUI removes it:

```swift
func makeNSView(context: Context) -> PlayerContainerView {
    let view = PlayerContainerView()
    view.onEnded = onEnded
    view.apply(cue)
    return view
}

func updateNSView(_ view: PlayerContainerView, context: Context) {
    view.onEnded = onEnded
    view.apply(cue)
}

static func dismantleNSView(_ view: PlayerContainerView, coordinator: ()) {
    view.teardown()
}
```

`PlayerContainerView` is the real machinery. Its `init` follows Apple's documented order for a *layer-hosting* view — set a backing `CALayer` first, then enable `wantsLayer`, then add the `AVPlayerLayer` set to aspect-fit:

```swift
layer = CALayer()
wantsLayer = true
playerLayer.videoGravity = .resizeAspect
layer?.addSublayer(playerLayer)
```

`required init?(coder:)` is marked `unavailable` (this view is never loaded from a storyboard). `layout()` keeps the player layer matching the view's `bounds` on every resize.

`apply(_:)` is the heart. First, an optimization: if the cue is unchanged, do nothing (don't restart a playing clip). Then tear down, record the cue, and — the safety line — bail to black if the file is missing:

```swift
func apply(_ cue: VideoCue) {
    guard cue != currentCue else { return }
    teardown()
    currentCue = cue
    playerLayer.isHidden = false

    // Graceful fallback: a missing file shows black rather than crashing.
    guard FileManager.default.fileExists(atPath: cue.url.path) else { return }
```

It builds an `AVPlayerItem` from a prewarmed asset (`VideoPrewarmer.shared.asset(for:)` — see that file), then branches on looping:

```swift
if cue.loops {
    let queue = AVQueuePlayer()
    looper = AVPlayerLooper(player: queue, templateItem: item)
    activePlayer = queue
} else {
    activePlayer = AVPlayer(playerItem: item)
    endObserver = NotificationCenter.default.addObserver(
        forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
    ) { [weak self] _ in
        MainActor.assumeIsolated { self?.handleEnd() }
    }
}
```

Looping clips get the seamless `AVQueuePlayer` + `AVPlayerLooper` combo. One-shot clips register an end observer; when the clip finishes, it calls `handleEnd()` on the main thread. The `[weak self]` avoids a retain cycle, and `MainActor.assumeIsolated` lets the (known-main-thread) notification run main-actor code.

Then it applies mute, attaches the player to the layer, and plays.

`handleEnd()` honors the cue's end behavior — if it's `.black`, hide the player layer (revealing black); then fire `onEnded` (which the output wires to auto-advance):

```swift
private func handleEnd() {
    if currentCue?.endBehavior == .black { playerLayer.isHidden = true }
    onEnded()
}
```

`teardown()` is thorough cleanup: remove the end observer, pause, detach the player from the layer, and null out the player, looper, and cue. This is what `dismantleNSView` calls so nothing leaks when the view goes away.

## How it connects

Mounted by `OutputView` when `LiveState.content` is `.video(cue)`. It consumes a `VideoCue` value snapshot (never a live model). It asks `VideoPrewarmer.shared` for a possibly-already-buffered asset to start faster. Its `onEnded` callback flows back up to `OutputView`, which calls `LiveState.next()` for clips set to advance.

## Gotchas / why it matters

- **Video must never crash the output** — the `guard FileManager.default.fileExists(...) else { return }` is the load-bearing safety line. Missing or bad file = black, not a crash.
- **Two playback paths by design:** `AVPlayerLooper` for seamless loops, plain `AVPlayer` + end observer for one-shots. Don't collapse them.
- **`[weak self]` + `teardown()`** prevent retain cycles and dangling observers — important because the output runs for a long service.
- **Hardware decode + aspect-fit** keep playback smooth and letterboxed; the output's black backdrop fills the bars.
- **Hardware-dependent:** smooth AVFoundation playback and start latency can only be truly verified by running on real hardware — headless tests can't prove it.
