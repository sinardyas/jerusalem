# Jerusalem

A native, macOS-only church presentation app — lyrics, Bible verses, sermon points,
and video, with a slide editor, built to **never fail on Sunday morning**.

See [`docs/`](docs/) for the MVP spec, the phased implementation plan, and the UI
prototypes.

## Requirements
- macOS 14+ (Sonoma)
- A recent Xcode (26.x tested)
- [XcodeGen](https://github.com/yonyz/XcodeGen): `brew install xcodegen`

## Build & run
The Xcode project is **generated** from [`project.yml`](project.yml) (the source of
truth) and is not committed. Generate it, then open or build:

```sh
xcodegen generate
open Jerusalem.xcodeproj          # work in Xcode
# — or from the command line —
xcodebuild -scheme Jerusalem -destination 'platform=macOS' build
```

## Status
**Phases 0–7 landed**, **Phase 8 Part 1 (WYSIWYG slide editor — mechanical
core)**, and the **Phase 9 code work** (reliability hardening). 68 tests, all
green.

The editor opens as a sheet from any slide thumbnail's right-click →
*Edit Slide…*: 8-handle drag/resize in normalized 0…1 coords, snap-to-grid +
alignment guides, safe-area overlay, zoom, Add Text / Add Image / Duplicate /
Delete / raise / lower, an inspector for typography + effects + slide
background, and ⌘Z / ⇧⌘Z via `ModelContext.undoManager`. A
`Slide.isManuallyEdited` flag tells `ContentRebuilder` to stop overwriting,
and a *Restore auto-generated slides* button on every content editor undoes
that yield. `SlideRenderer` now draws image elements as well as text.

Phase 9 code work landed:
- **Last-position persistence** (`LastPosition`) — the operator's selection
  survives quit/relaunch via stable UUIDs.
- **Pre-rendered upcoming slides** (`SlidePrewarmer`) — bounded LRU cache,
  prewarmed off `LiveState.nextProgramSlide` changes at the audience
  output's pixel size; `RenderableSlideView`'s `.task` routes through the
  same cache so re-mounts are free.
- **Missing-media audit** (`MediaAudit`) — slide grid thumbnails show a
  yellow ⚠ when any referenced file isn't on disk.
- **Stress fixture** (`StressTests`) — synthetic 10-song + 4-video playlist
  walked 200 next() + 200 previous() asserts no crash + non-empty content;
  prewarmer LRU bound + cache hit identity covered.

**The Phase 9 *gate* is fundamentally hardware**: zero crashes / freezes /
lag during a complete dress-rehearsal service, including external display
unplug/replug. The XCTest suite covers what it can; run through
[`docs/DRESS-REHEARSAL.md`](docs/DRESS-REHEARSAL.md) on a real Mac with a
second display for the rest. The same caveat applies to the Phase 8
"non-designer designs a good-looking slide in under a minute" UX gate.

The bundled Bible dataset is a starter (John 3, Psalm 23, Rom 8:28, Phil 4:13
in KJV + WEB). For full KJV/WEB, fetch public-domain OSIS XML and convert it
via [`Tools/build-bible-db/README.md`](Tools/build-bible-db/README.md).

Deferred from Phase 8 Part 2 / Phase 9 to a follow-up: gradient backgrounds,
"set as default style" theme save, the AppKit / Core Animation canvas swap
(if SwiftUI gesture precision turns out to be insufficient on real hardware),
multi-select / copy-paste, and Instruments-based perf profiling.

Next gate: **Phase 10 — Packaging & release prep** (icon, code signing +
notarization, onboarding, sample content, crash reporting, updater).
Roadmap and checkpoints:
[`docs/IMPLEMENTATION-PLAN.md`](docs/IMPLEMENTATION-PLAN.md).
