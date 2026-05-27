# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Jerusalem is a **native, macOS-only** church presentation app (lyrics, Bible verses,
sermon points, video) with a slide editor, built around one promise: **never fail on
Sunday morning**. SwiftUI for chrome, AppKit/AVFoundation where SwiftUI is weak,
SwiftData for persistence. macOS 14 minimum.

The product spec is `docs/MVP.md`; the build sequence is `docs/IMPLEMENTATION-PLAN.md`.
Read the plan before adding features — it is the source of truth for scope and ordering.

## Build, run, test

The Xcode project is **generated from `project.yml` (the source of truth) via XcodeGen
and is not committed**. After cloning, or after changing `project.yml` / adding/removing
source files, regenerate it:

```sh
brew install xcodegen          # one-time
xcodegen generate              # regenerates Jerusalem.xcodeproj
```

```sh
# Build
xcodebuild -scheme Jerusalem -destination 'platform=macOS' build

# All tests
xcodebuild test -scheme Jerusalem -destination 'platform=macOS'

# A single test class or method
xcodebuild test -scheme Jerusalem -destination 'platform=macOS' \
  -only-testing:JerusalemTests/LiveNavigationTests
xcodebuild test -scheme Jerusalem -destination 'platform=macOS' \
  -only-testing:JerusalemTests/LiveNavigationTests/testGoLiveByID
```

The single scheme `Jerusalem` builds both the app and the `JerusalemTests` bundle.
There is no linter configured (the plan mentions SwiftLint/SwiftFormat as future hygiene).

## Architecture: the invariants that must hold

These cross-cutting rules are what make the reliability promise true. Preserve them in
every change.

**1. One shared renderer.** `SlideRenderer.makeImage` (`Rendering/SlideRenderer.swift`)
is the *single* path that turns a slide into a `CGImage` — used identically by grid
thumbnails, the inspector preview, and the live audience output. Never add a second
rendering path. It draws text via AppKit/TextKit (stroke, shadow, alignment, line
spacing, auto-fit) and **must run on the main thread**; views drive it from `View.task`
keyed on content+pixel-size so it re-renders only on real changes (`Rendering/SlideView.swift`).

**2. Edit/live separation via value snapshots.** The renderer and the live output work
*only* on immutable value types — `RenderableSlide` / `RenderableElement` / `VideoCue`
(`Rendering/RenderableSlide.swift`, `Media/VideoCue.swift`) — never on live SwiftData
models. `LiveState` (`Live/LiveState.swift`) holds a resolved snapshot in `content`;
editing a model in the operator window therefore cannot change what's on the audience
screen until the operator acts. A program is *armed* (loaded) without changing output;
`next()` / `goLive(id:)` start it. Panic states (Black/Clear/Logo) and transitions live
here too. When you touch live behavior, snapshot the model into a value type — do not
pass a `@Model` object toward the renderer.

**3. Normalized coordinates.** `SlideElement` frames are stored in 0...1 (top-left
origin) and `fontSize` is in points at a 1920×1080 reference, so slides scale to any
output resolution. Keep new geometry normalized.

**4. AppKit owns the output window.** `OutputController` (`Live/OutputController.swift`,
`@MainActor @Observable`) places an `NSWindow` on a chosen `NSScreen`, borderless +
full-screen on an external display, a resizable preview when there's only one display.
It observes `didChangeScreenParameters` to survive resolution changes and display
unplug/replug (fail over to a remaining screen, never crash). `ScreenSelection.outputIndex`
is the pure, tested rule for *which* screen.

**5. Video must never crash the output.** `VideoPlayerView` (`Live/VideoPlayerView.swift`,
an `NSViewRepresentable` over `AVPlayerLayer`) hardware-decodes mp4/mov, loops via
`AVQueuePlayer`+`AVPlayerLooper`, and falls back to black for missing/unplayable files.
`VideoPrewarmer` (a `@MainActor` singleton) pre-buffers the *next* clip to reduce start
latency.

## Persistence (SwiftData)

`Persistence.makeContainer` (`Persistence/Persistence.swift`) builds the shared,
autosaving on-disk container; `Persistence.schema` lists the model roots (SwiftData
discovers the rest through relationships). The main context **autosaves by default** —
that is the crash-recovery foundation, so avoid patterns that defeat it. `SampleData`
seeds one song + playlist on an empty store (idempotent), giving the app something to
show on first launch.

Models live in `Models/`: `Item` (song/bible/text/media) → ordered `Slide`s → ordered
`SlideElement`s; `Playlist` ↔ `Item` via the `PlaylistEntry` join model (so an item can
sit in many playlists with per-playlist ordering); `Theme`. **SwiftData convention here:**
enums are stored as a private `…Raw: String` property with a computed accessor (see
`Item.kind`, `SlideElement.alignment`, `Item.videoEndBehavior`) — follow this when adding
enum-typed model fields. Ordered relationships are exposed via `orderedSlides` /
`orderedElements` / `orderedEntries` computed sorts.

## Conventions

- **Pure logic is extracted into caseless `enum` namespaces** so it's unit-testable
  without UI/AppKit/SwiftData: `MediaImport` (file-type rules), `MediaStorage` (on-disk
  import under Application Support/Jerusalem/Media), `LibrarySearch`, `ScreenSelection`,
  `SampleData`, `Persistence`, `SlideRenderer`. When adding behavior, push the decidable
  rule into such a type and keep views thin.
- **State injection:** `LiveState` and `OutputController` are created once in
  `JerusalemApp` and passed down with `.environment(...)`, read via `@Environment(Type.self)`.
- **Keyboard control:** the operator window installs a local `NSEvent` key monitor
  (`OperatorView.installKeyMonitor`) — arrows/space navigate, B/C/L panic — and ignores
  keys while a text field is focused. `MainActor.assumeIsolated` is used inside AppKit
  callbacks that are known to fire on the main thread.

## Phased development discipline

Work proceeds through gated phases (`docs/IMPLEMENTATION-PLAN.md`); **each gate is a hard
stop** — a runnable, demonstrable milestone — and you do not advance until it passes.
Phases 0–5 are implemented (foundation, SwiftData model, the shared renderer, dual-screen
live output, keyboard control, and the video engine). Tests map directly to these gates:
`PersistenceTests` (Phase 1), `SlideRenderingTests` (Phase 2), `LiveOutputTests` (Phase 3),
`LiveNavigationTests` (Phase 4), `MediaTests` (Phase 5). Add a gate test alongside each
phase you complete.

Because the highest-risk pillars (rendering, output, video) were front-loaded, **the
programmatic parts are covered by headless XCTest, but the truly hardware-dependent
behavior is not** — full-screen output, AVFoundation playback smoothness, and
display unplug/replug resilience must be verified by running the app on real hardware
with a second display. Note this when claiming a video or output change "works."
