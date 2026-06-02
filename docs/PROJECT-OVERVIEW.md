# Jerusalem — Project Overview

> A discovery summary of this codebase for newcomers. For authoritative detail, see
> [`MVP.md`](MVP.md) (product spec), [`IMPLEMENTATION-PLAN.md`](IMPLEMENTATION-PLAN.md)
> (build sequence), [`DRESS-REHEARSAL.md`](DRESS-REHEARSAL.md) (hardware gate), and
> [`../CLAUDE.md`](../CLAUDE.md) (architecture invariants).

## What it is

**Jerusalem** is a native, **macOS-only** church presentation app — it projects **song
lyrics, Bible verses, sermon/text points, and video** onto a second screen (projector/TV)
during a live service, and ships with a WYSIWYG **slide editor** to design how that content
looks.

The entire product is organized around one promise: **never fail on Sunday morning.**
Reliability, speed, and native macOS integration are treated as first-class features — the
explicit contrast is with ProPresenter (powerful, but criticized for being heavy, slow, and
crash-prone mid-service).

- **Target user:** volunteer / part-time operators at small-to-medium churches who prepare
  slides during the week and run the service on Sunday — ideally without reading a manual.
- **Platform:** macOS 14 (Sonoma) minimum. No iOS/iPad variant in scope.

## Tech stack

| Concern | Technology |
|---|---|
| App chrome / UI | **SwiftUI** |
| Output window & editor canvas | **AppKit** (`NSWindow` / `NSScreen`) where SwiftUI is weak |
| Text fidelity (stroke, auto-fit, spacing) | **Core Text / TextKit** |
| Video playback | **AVFoundation** (`AVPlayer`/`AVPlayerLayer`, `AVQueuePlayer` + `AVPlayerLooper`) |
| Persistence | **SwiftData** (SQLite-backed), autosaving on-disk container |
| Project generation | **XcodeGen** — `Jerusalem.xcodeproj` is generated from `project.yml` and **not committed** |

Bundle id `id.soechi.Jerusalem`; product version 0.1.0; Swift 5.0; hardened runtime enabled.

## Architecture invariants

These cross-cutting rules are what make the reliability promise hold. Preserve them in every
change (see [`../CLAUDE.md`](../CLAUDE.md)).

1. **One shared renderer.** `Rendering/SlideRenderer.swift` (`makeImage`) is the *single* path
   that turns a slide into a `CGImage` — used identically by grid thumbnails, the inspector
   preview, and the live audience output. It draws text via AppKit/TextKit and **must run on
   the main thread**. Never add a second rendering path.
2. **Edit/live separation via value snapshots.** The renderer and live output work *only* on
   immutable value types — `RenderableSlide` / `RenderableElement` (`Rendering/`) and `VideoCue`
   (`Media/`) — never on live SwiftData `@Model` objects. `LiveState` (`Live/LiveState.swift`)
   holds a resolved snapshot, so editing a model can't change what's on screen until the
   operator acts (`next()` / `goLive(id:)`).
3. **Normalized coordinates.** `SlideElement` frames are stored in `0…1` (top-left origin) and
   `fontSize` is in points at a 1920×1080 reference, so slides scale to any output resolution.
4. **AppKit owns the output window.** `Live/OutputController.swift` (`@MainActor @Observable`)
   places an `NSWindow` on a chosen `NSScreen` — borderless full-screen on an external display,
   resizable preview when there's only one — and observes `didChangeScreenParameters` to survive
   resolution changes and display unplug/replug without crashing.
5. **Video must never crash the output.** `Live/VideoPlayerView.swift` hardware-decodes mp4/mov
   and loops; `VideoPrewarmer` pre-buffers the *next* clip. Missing/unplayable files fall back to
   black rather than crashing.

## Repository structure

```
bold-hare/
├── Sources/Jerusalem/      # App source (organized by domain — see table below)
├── Tests/JerusalemTests/   # XCTest suite — 13 classes, one per phase gate
├── Tools/build-bible-db/   # Standalone tool: OSIS/Zefania XML → bundled bible JSON
├── docs/                   # MVP.md, IMPLEMENTATION-PLAN.md, DRESS-REHEARSAL.md, plans, prototypes
├── project.yml             # XcodeGen manifest — the source of truth (xcodeproj is generated)
├── CLAUDE.md               # Architecture invariants & conventions
└── README.md               # Build/run instructions & phase status
```

### Source folders (`Sources/Jerusalem/`)

| Folder | Responsibility |
|---|---|
| `Models/` | SwiftData models: `Item`, `Slide`, `SlideElement`, `SongSection`, `Playlist` (+ `PlaylistEntry` join), `Theme`, `BibleVerse` |
| `Persistence/` | `Persistence` (container/schema/autosave), `BibleSeeder`, `SampleData`, `LastPosition` (session restore) |
| `Content/` | Authoring logic: `SlideSplitter`, `ContentRebuilder`, `SongLyricsParser`, `BibleReferenceParser`, `BibleBookCatalog`, `BibleStore`, `DefaultTheme` |
| `Rendering/` | `SlideRenderer`, `RenderableSlide` (value snapshot), `SlideView`, `SlidePrewarmer` (LRU cache) |
| `Live/` | `LiveState`, `OutputController`, `OutputView`, `VideoPlayerView`, `VideoPrewarmer` |
| `Editor/` | WYSIWYG slide editor: canvas, drag/resize handles, inspector, layers, zoom, inline text |
| `Views/` | `OperatorView` (main window) + sidebar/grid/inspector + Song/Bible/Sermon sheet editors |
| `Media/` | Media import rules & storage, `VideoCue`, `MediaAudit` (missing-file warnings) |
| `Support/` | Utilities: `ColorHex`, `LibrarySearch` |
| `Resources/` | `bible-starter.json` (KJV + WEB starter scripture) |

### App entry point

`JerusalemApp.swift` (`@main`) creates `LiveState`, an `OutputController` observing it, and the
shared SwiftData container once, then injects `live` + `output` via `.environment(...)`. It
declares two windows:

- **`operator`** — `OperatorView`, the main control surface.
- **`slide-editor`** — opened on demand for a specific `Item` (keyed by `PersistentIdentifier`).

## Data model

The content aggregate is rooted at `Item` and rendered through immutable snapshots:

```
Item (song | bible | text | media)
├── slides: [Slide]            (ordered; rebuilt from sources unless isManuallyEdited)
│     └── elements: [SlideElement]   (ordered back-to-front; text/image/shape, normalized 0…1)
├── songSections: [SongSection]      (verse/chorus/bridge/tag — songs only)
├── theme: Theme?                    (defaults to DefaultTheme)
└── playlistEntries: [PlaylistEntry] (an item can appear in many playlists)

Playlist ──< PlaylistEntry >── Item        (ordered join, per-playlist ordering)
BibleVerse                                  (read-only, seeded from bible-starter.json)
```

**Rendering snapshots (not SwiftData):** `RenderableSlide`, `RenderableElement`, `VideoCue` —
immutable value copies that decouple the renderer/live output from persistence.

**SwiftData convention:** enums are stored as a private `…Raw: String` with a computed accessor
(e.g. `Item.kind`, `SlideElement.alignment`); ordered relationships are exposed via
`orderedSlides` / `orderedElements` / `orderedEntries`. The main context **autosaves** — that is
the crash-recovery foundation.

## Feature set (MVP)

- **Content:** songs with auto-split sections; offline Bible lookup (KJV/WEB) with reference
  parsing (`John 3:16-18`) and passage auto-split; sermon/text slides; full-screen and looping
  background video.
- **Slide editor:** 16:9 (or 4:3) canvas; add/drag/resize text & images; layer ordering;
  font/size/color/alignment/spacing, stroke & drop shadow; auto-fit; snap-to-grid, alignment
  guides, safe-area overlay; undo/redo.
- **Library & playlists:** searchable library; multiple drag-to-reorder playlists per service.
- **Live control:** slide grid → click to go live; keyboard nav (→/↓/Space next, ←/↑ previous);
  **panic hotkeys** (Black / Clear / Logo); cut & fade transitions; video transport.
- **Reliability:** edit/live separation, autosave + crash recovery, fast cold launch with
  pre-rendered upcoming slides, graceful missing-media handling, resilient full-screen output.

**Non-goals (deferred):** advanced video trimming, stage/confidence display, reusable template
library, multiple outputs, lower thirds, NDI/Syphon, imports from other apps, iPad remote,
iCloud sync, CCLI/paid translations.

## Phase status

Development proceeds through gated phases — each ends in a runnable, testable milestone (see
[`IMPLEMENTATION-PLAN.md`](IMPLEMENTATION-PLAN.md)).

| Phase | Scope | Status |
|---|---|---|
| 0 | Foundation & app shell | ✅ Done |
| 1 | Domain model & persistence | ✅ Done |
| 2 | Slide rendering core | ✅ Done |
| 3 | Live output & dual-screen | ✅ Done |
| 4 | Live control & navigation | ✅ Done |
| 5 | Video & media engine | ✅ Done |
| 6 | Songs & text content | ✅ Done |
| 7 | Bible content (offline) | ✅ Done |
| 8 | Slide editor (WYSIWYG) | ✅ Code done (Part 1 mechanical core); UX gate hardware-pending |
| 9 | Reliability hardening & dress rehearsal | ✅ Code done; **gate is hardware-dependent** |
| 10 | Packaging & release (signing, notarization, onboarding, crash reporting, updater) | ⏳ Pending |

**68 tests, all green.** Two gates remain hardware-dependent and cannot be proven by headless
tests: Phase 8 ("a non-designer makes a good-looking slide in under a minute") and Phase 9 (a
complete dress-rehearsal service with zero crashes/lag, including display unplug/replug — see
[`DRESS-REHEARSAL.md`](DRESS-REHEARSAL.md)).

## Build, run & test

```sh
brew install xcodegen            # one-time
xcodegen generate                # regenerate Jerusalem.xcodeproj after project.yml or file changes

# Build
xcodebuild -scheme Jerusalem -destination 'platform=macOS' build

# All tests
xcodebuild test -scheme Jerusalem -destination 'platform=macOS'

# A single test class or method
xcodebuild test -scheme Jerusalem -destination 'platform=macOS' \
  -only-testing:JerusalemTests/LiveNavigationTests
```

There is **no linter or CI** configured yet (SwiftLint/SwiftFormat are noted as future hygiene).

### Tests → phase mapping

| Test class | Phase |
|---|---|
| `AppSmokeTests` | 0 |
| `PersistenceTests` | 1 |
| `SlideRenderingTests` | 2 |
| `LiveOutputTests` | 3 |
| `LiveNavigationTests` | 4 |
| `MediaTests` | 5 |
| `SongContentTests` | 6 |
| `BibleTests` | 7 |
| `SlideEditorTests`, `SlideEditorPart2Tests`, `SlideShapeTests`, `SlideLayersTests` | 8 |
| `StressTests` | 9 |

The renderer, navigation, and persistence are well covered headlessly. Hardware-dependent
behavior — full-screen output, AVFoundation playback smoothness, display unplug/replug — must be
verified by running the app on a real Mac with a second display.

## Where to look next

- **Architecture rules & conventions:** [`../CLAUDE.md`](../CLAUDE.md)
- **Product spec & scope:** [`MVP.md`](MVP.md)
- **Build sequence & gates:** [`IMPLEMENTATION-PLAN.md`](IMPLEMENTATION-PLAN.md)
- **Hardware verification checklist:** [`DRESS-REHEARSAL.md`](DRESS-REHEARSAL.md)
- **The single renderer:** `Sources/Jerusalem/Rendering/SlideRenderer.swift`
- **Live program state:** `Sources/Jerusalem/Live/LiveState.swift`
- **Output window management:** `Sources/Jerusalem/Live/OutputController.swift`
