# `VideoPlayerView.swift`

> A SwiftUI wrapper around AVFoundation video playback for the audience output — hardware-decoded, looping or one-shot, and engineered to fall back to black rather than ever crash.

**Location:** `Sources/Jerusalem/Live/VideoPlayerView.swift`
**Role:** NSViewRepresentable (+ its backing AppKit view)

## What it does (plain English)

SwiftUI has no good native way to play a video onto a layer with precise control, so this file drops down to AppKit and AVFoundation. `VideoPlayerView` is the thin SwiftUI shell; the real work is in `PlayerContainerView`, a hand-written AppKit `NSView` that hosts an `AVPlayerLayer` (the surface that shows decoded frames).

Given a `VideoCue` (a value snapshot describing a clip), it builds the right kind of player. For looping clips it uses `AVQueuePlayer` + `AVPlayerLooper` (seamless loops). For one-shot clips it uses a plain `AVPlayer` and listens for the "played to end" event to fire its `onEnded` callback. It hardware-decodes via the GPU and letterboxes (aspect-fit), so the black output shows through around the edges.

The safety story is everything: if the file is missing or unplayable, it shows nothing (black) instead of throwing. Video must never take down the live output.

## Swift you'll meet in this file

- `NSViewRepresentable` — a SwiftUI protocol for wrapping an AppKit `NSView` so it can be used like a SwiftUI view. `// analogy:` a React wrapper around a non-React widget. You implement `makeNSView` (create), `updateNSView` (sync props), and optionally `dismantleNSView` (cleanup on removal).
- `NSView` — a UI box in the old AppKit layer → a raw DOM-ish widget you manipulate imperatively.
- `CALayer` / layer-backed view (`wantsLayer = true`) — the Core Animation layer that actually draws → a GPU-backed drawing surface.
- `AVPlayerLayer` — the layer that displays video frames. `// analogy:` the rendering surface of an HTML `<video>` element.
- `AVPlayer` / `AVQueuePlayer` / `AVPlayerItem` / `AVPlayerLooper` — AVFoundation's playback engine pieces. `// analogy:` the `<video>` element + its source + a JS loop helper.
- `NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, ...)` — subscribing to the "clip finished" OS event → `videoEl.addEventListener("ended", …)`.
- `[weak self]` — `// non-retaining ref (avoid leak)`: a capture that won't keep the view alive, breaking a retain cycle between observer and view.
- `MainActor.assumeIsolated { ... }` — "I know this callback already runs on the main thread" → `// already on the UI thread; run main-thread code without awaiting`.
- `@available(*, unavailable)` — marks `init(coder:)` as forbidden (compile error if used).
- `final class`, `var`, optionals (`AVPlayer?`), `guard ... else { return }` early exits.
- Closures `{ ... }` = arrow functions; `onEnded: () -> Void = {}` is a callback prop with a default no-op → `onEnded: () => void = () => {}`.

## Code walkthrough

`VideoPlayerView` is the SwiftUI bridge. It just forwards the cue and callback into the AppKit view at create-and-update time, and tears the player down when SwiftUI removes it:

```swift
struct VideoPlayerView: NSViewRepresentable {
    let cue: VideoCue
    var onEnded: () -> Void = {}

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
}
```

**TypeScript equivalent**

```ts
// NSViewRepresentable ⇒ a React wrapper around a non-React widget.
// analogy: a class component that creates a raw widget in componentDidMount,
// pushes new props in componentDidUpdate, and cleans up in componentWillUnmount.
const VideoPlayerView = {
  cue: undefined as unknown as VideoCue,
  onEnded: (() => {}) as () => void,   // default no-op callback prop

  makeNSView(): PlayerContainerView {          // create the widget
    const view = new PlayerContainerView();
    view.onEnded = this.onEnded;
    view.apply(this.cue);
    return view;
  },

  updateNSView(view: PlayerContainerView) {    // sync props on re-render
    view.onEnded = this.onEnded;
    view.apply(this.cue);
  },

  dismantleNSView(view: PlayerContainerView) { // cleanup on removal
    view.teardown();
  },
};
```

**Swift syntax:**
- `struct VideoPlayerView: NSViewRepresentable` — conforming to `NSViewRepresentable` is the contract that says "I wrap an `NSView`." SwiftUI calls your `makeNSView` once, `updateNSView` on every state change, and `dismantleNSView` (static) on removal — exactly the mount/update/unmount lifecycle.
- `var onEnded: () -> Void = {}` — a stored closure property typed `() -> Void` (no args, no return) with a default empty closure `{}`. A callback prop defaulting to a no-op.
- `func makeNSView(context:)` / `func updateNSView(_:context:)` — the required lifecycle methods; `_ view` drops the external label so the call site is positional.

`PlayerContainerView` is the real machinery. Its `init` follows Apple's documented order for a *layer-hosting* view — set a backing `CALayer` first, then enable `wantsLayer`, then add the `AVPlayerLayer` set to aspect-fit:

```swift
final class PlayerContainerView: NSView {
    private let playerLayer = AVPlayerLayer()
    private var player: AVPlayer?
    private var looper: AVPlayerLooper?
    private var endObserver: NSObjectProtocol?
    private var currentCue: VideoCue?
    var onEnded: () -> Void = {}

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer = CALayer()
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
```

**TypeScript equivalent**

```ts
class PlayerContainerView /* extends NSView */ {
  private readonly playerLayer = new AVPlayerLayer();
  private player: AVPlayer | null = null;
  private looper: AVPlayerLooper | null = null;
  private endObserver: NSObjectProtocol | null = null;
  private currentCue: VideoCue | null = null;
  onEnded: () => void = () => {};

  constructor(frameRect: NSRect) {
    super(frameRect);
    // Apple's documented order for a layer-hosting view:
    this.layer = new CALayer();        // 1. backing layer first
    this.wantsLayer = true;            // 2. then opt into layers
    this.playerLayer.videoGravity = "resizeAspect"; // letterbox (aspect-fit)
    this.layer?.addSublayer(this.playerLayer);      // 3. attach the video layer
  }

  // init(coder:) is forbidden — never loaded from a storyboard
  // (no TS equivalent; just don't construct it that way)

  layout() {                  // called on every resize
    super.layout();
    this.playerLayer.frame = this.bounds;  // keep the video layer filling the view
  }
}
```

**Swift syntax:**
- `final class PlayerContainerView: NSView` — subclasses AppKit's `NSView`. `final` = not subclassable.
- `private let playerLayer = AVPlayerLayer()` vs `private var player: AVPlayer?` — `let` is a constant stored property; `var` with `?` is a reassignable optional, initialized to `nil` implicitly.
- `override init(frame:)` then `super.init(frame:)` — overriding the designated initializer; you must call `super.init` to set up the `NSView` base.
- `@available(*, unavailable) required init?(coder:)` — `required` means subclasses must provide it, but `@available(*, unavailable)` makes any *use* a compile error. The standard "this view is never decoded from a nib/storyboard" pattern. `init?` is a *failable* initializer (can return `nil`).
- `override func layout()` — AppKit calls this on resize; you sync the sublayer's frame to `bounds` (the view's own rect).

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

**TypeScript equivalent**

```ts
apply(cue: VideoCue) {
  // skip if nothing changed — don't restart a playing clip
  if (deepEqual(cue, this.currentCue)) return;   // guard cue != currentCue
  this.teardown();
  this.currentCue = cue;
  this.playerLayer.isHidden = false;

  // LOAD-BEARING SAFETY LINE: missing file ⇒ show black, never throw
  if (!fileExists(cue.url.path)) return;         // guard … else { return }
  // …builds the player below
}
```

It builds an `AVPlayerItem` from a prewarmed asset (`VideoPrewarmer.shared.asset(for:)` — see that file), then branches on looping:

```swift
let item = AVPlayerItem(asset: VideoPrewarmer.shared.asset(for: cue.url))
let activePlayer: AVPlayer
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
activePlayer.isMuted = cue.muted
playerLayer.player = activePlayer
player = activePlayer
activePlayer.play()
```

**TypeScript equivalent**

```ts
// reuse a possibly-prewarmed asset so playback starts faster
const item = new AVPlayerItem(VideoPrewarmer.shared.asset(cue.url));
let activePlayer: AVPlayer;

if (cue.loops) {
  // seamless looping: queue player + looper (analogy: <video loop>)
  const queue = new AVQueuePlayer();
  this.looper = new AVPlayerLooper(queue, item);
  activePlayer = queue;
} else {
  // one-shot: plain player + listen for the "ended" event
  activePlayer = new AVPlayer(item);
  this.endObserver = NotificationCenter.default.addObserver(
    "AVPlayerItemDidPlayToEndTime", item, "main",
    // [weak self]: non-retaining ref (avoid leak between observer and view)
    () => {
      // already on the UI thread; run main-thread code without awaiting
      this /*?*/.handleEnd();
    });
}

activePlayer.isMuted = cue.muted;
this.playerLayer.player = activePlayer;          // attach to the drawing surface
this.player = activePlayer;
activePlayer.play();
```

**Swift syntax:**
- `let activePlayer: AVPlayer` then assigned in both branches — Swift allows declaring a `let` and assigning it exactly once later (definite-initialization), so both `if`/`else` paths set it.
- `addObserver(forName:object:queue:) { [weak self] _ in … }` — the trailing closure is the handler. `[weak self]` is a *capture list* making `self` a weak (non-retaining) reference so the observer doesn't keep the view alive (prevents a retain cycle / leak). The `_` ignores the notification argument.
- `self?.handleEnd()` — optional-chains through the now-weak `self`; if the view was already freed, it's a safe no-op.
- `MainActor.assumeIsolated { … }` — asserts "this closure is already on the main thread," letting it call `@MainActor`-isolated code synchronously (no `await`). Use only where the callback genuinely fires on main (here, `queue: .main`).

Looping clips get the seamless `AVQueuePlayer` + `AVPlayerLooper` combo. One-shot clips register an end observer; when the clip finishes, it calls `handleEnd()` on the main thread. The `[weak self]` avoids a retain cycle, and `MainActor.assumeIsolated` lets the (known-main-thread) notification run main-actor code. Then it applies mute, attaches the player to the layer, and plays.

`handleEnd()` honors the cue's end behavior — if it's `.black`, hide the player layer (revealing black); then fire `onEnded` (which the output wires to auto-advance):

```swift
private func handleEnd() {
    if currentCue?.endBehavior == .black { playerLayer.isHidden = true }
    onEnded()
}
```

**TypeScript equivalent**

```ts
private handleEnd() {
  // .black ⇒ hide the video layer so the black backdrop shows
  if (this.currentCue?.endBehavior === "black") this.playerLayer.isHidden = true;
  this.onEnded();   // tells OutputView → LiveState.next() for "advance"
}
```

`teardown()` is thorough cleanup: remove the end observer, pause, detach the player from the layer, and null out the player, looper, and cue:

```swift
func teardown() {
    if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    endObserver = nil
    player?.pause()
    playerLayer.player = nil
    player = nil
    looper = nil
    currentCue = nil
}
```

**TypeScript equivalent**

```ts
teardown() {
  // if let endObserver { … } ⇒ unwrap-and-use the optional
  if (this.endObserver) NotificationCenter.default.removeObserver(this.endObserver);
  this.endObserver = null;
  this.player?.pause();          // optional chaining — no-op if already null
  this.playerLayer.player = null;
  this.player = null;
  this.looper = null;
  this.currentCue = null;
}
```

**Swift syntax:**
- `if let endObserver { … }` — Swift 5.7+ shorthand for `if let endObserver = endObserver`: unwraps the optional and shadows it with the same name inside the block. Like `if (this.endObserver) { … }` after a null check.

This is what `dismantleNSView` calls so nothing leaks when the view goes away.

## How it connects

Mounted by `OutputView` when `LiveState.content` is `.video(cue)`. It consumes a `VideoCue` value snapshot (never a live model). It asks `VideoPrewarmer.shared` for a possibly-already-buffered asset to start faster. Its `onEnded` callback flows back up to `OutputView`, which calls `LiveState.next()` for clips set to advance.

## Gotchas / why it matters

- **Video must never crash the output** — the `guard FileManager.default.fileExists(...) else { return }` is the load-bearing safety line. Missing or bad file = black, not a crash.
- **Two playback paths by design:** `AVPlayerLooper` for seamless loops, plain `AVPlayer` + end observer for one-shots. Don't collapse them.
- **`[weak self]` + `teardown()`** prevent retain cycles and dangling observers — important because the output runs for a long service.
- **Hardware decode + aspect-fit** keep playback smooth and letterboxed; the output's black backdrop fills the bars.
- **Hardware-dependent:** smooth AVFoundation playback and start latency can only be truly verified by running on real hardware — headless tests can't prove it.
