# Jerusalem — MVP Implementation Plan (Phased Checkpoints)

## Context

This plan turns the approved MVP (`docs/MVP.md`) and the chosen UI direction
(**Prototype C + slide editor**, see `docs/prototypes/mvp/`) into a buildable
sequence. It is split into **phases that are checkpoints**: each phase ends in a
*runnable, demonstrable, testable* milestone (a **gate**). **Do not advance to the
next phase until the current gate passes.** This keeps the reliability promise —
"never fails on Sunday" — verifiable at every step instead of only at the end.

Ordering principle: **front-load the riskiest, reliability-critical pillars**
(the shared render pipeline, the dual-screen output, and video) *before* breadth of
content and the large editor. By Phase 5 you can already run a real (text + video)
service; the editor and content authoring build on a proven foundation.

> Sizes are relative effort (S / M / L / XL), not calendar estimates.

---

## Technical foundation (recap)

- **macOS 14 (Sonoma) minimum** ✅ — to use `.inspector`, `onKeyPress`, modern
  `NavigationSplitView`.
- **SwiftUI** for app chrome; **AppKit** where SwiftUI is weak (output window, possibly
  the editor canvas) via `NSHostingView` / `NSViewRepresentable`.
- **Core Text / TextKit 2** for text fidelity (stroke/outline, auto-fit).
- **AVFoundation** (`AVPlayer`/`AVPlayerLayer`, `AVQueuePlayer`) for video.
- **Persistence:** **SwiftData** ✅ (native, macOS 14+; SQLite-backed).
- **One shared `SlideRenderer`** renders the slide model everywhere (thumbnail,
  preview, live output). Build it once; never duplicate rendering.

---

## Phase 0 — Foundation & app shell  · S
**Goal:** A launchable app with the Prototype C skeleton and project hygiene in place.
**Build:**
- Xcode project (SwiftUI App lifecycle), macOS 14 target, Swift package structure,
  git, basic SwiftLint/format, scheme for tests.
- The 3-pane shell: `NavigationSplitView` (sidebar · content) + `.inspector` (trailing),
  unified `.toolbar`, with placeholder/empty-state content.
**Frameworks:** SwiftUI.
**✓ Checkpoint (gate):** App builds and launches to the Prototype C layout with empty
states; window restores size/position; CI (or `xcodebuild`) builds green.

## Phase 1 — Domain model & persistence  · M
**Goal:** The data that everything else reads/writes, with autosave + restore.
**Build:**
- Model types: `Library`, `Playlist` (ordered, named, savable), `Item`
  (Song / Bible / Text / Media), `Slide`, `SlideElement` (text/image), `Theme`.
- Persistence layer (SwiftData recommended); **autosave** + load on launch; atomic
  writes; a migration-friendly schema.
- Seed/sample data for development.
**Frameworks:** SwiftData (or SQLite), Foundation.
**✓ Checkpoint (gate):** Create a song and a playlist in code/UI, quit, relaunch →
state is fully restored. Confirms the **autosave / crash-recovery foundation**.
**Decided:** SwiftData (native, macOS 14+, SQLite-backed).

## Phase 2 — Slide rendering core  · L
**Goal:** The single source of truth for *what a slide looks like* — used by thumbnails,
preview, and live output.
**Build:**
- `SlideRenderer` that draws a `Slide` (background + text/image elements) at a target
  size and aspect ratio (16:9 / 4:3).
- Text via **Core Text / TextKit 2**: font, size, color, alignment, line/letter
  spacing, **stroke/outline**, **shadow**, **auto-fit** (measure → fit-to-box).
- Background: solid / gradient / image (video deferred to Phase 5).
**Frameworks:** Core Text/TextKit, Core Graphics / Core Animation, SwiftUI `Canvas`.
**✓ Checkpoint (gate):** Render a styled slide on screen at correct aspect ratio; the
sidebar/grid show real thumbnails generated from the model; text auto-fits its box.

## Phase 3 — Live output & dual-screen  · L  *(reliability-critical)*
**Goal:** A rock-solid full-screen audience output on a second display, decoupled from editing.
**Build:**
- AppKit `NSWindow` placed on a chosen `NSScreen` (`NSScreen.screens`), borderless
  full-screen, hosting `SlideRenderer` output via `NSHostingView`.
- **Edit/live separation:** output reads a `LiveState`; editing never blocks output.
- Robust handling of display sleep, resolution change, unplug/replug; auto-detect
  the external display.
**Frameworks:** AppKit (NSWindow/NSScreen), SwiftUI hosting.
**✓ Checkpoint (gate):** Operator window + audience output on a 2nd display; pushing a
slide live shows it full-screen; **unplug/replug the display mid-show without a crash**;
editing in the operator window never stalls the output.

## Phase 4 — Live control & navigation  · M
**Goal:** Run a service from the keyboard (text slides only, for now).
**Build:**
- Slide grid → click to go live; **Live + Next** preview in the inspector.
- Keyboard nav: **→ / ↓ / Space** (next), **← / ↑** (prev) via `onKeyPress`.
- **Panic** hotkeys: Black / Clear / Logo. Transitions: **cut + fade**.
- Search-and-go-live.
**Frameworks:** SwiftUI, Core Animation (transitions).
**✓ Checkpoint (gate):** Build a mock playlist of text slides and **run the whole thing
using only the keyboard**; panic keys instantly affect the live output; fade is smooth.

## Phase 5 — Video & media engine  · L  *(differentiator — de-risk early)*
**Goal:** Prove flawless video on the live output, the feature ProPresenter fails at.
**Build:**
- **Formats (MVP):** **.mp4 / .mov** (H.264 / HEVC), hardware-decoded via AVFoundation.
- Import video/image into the **media library** (thumbnails).
- Video as a **full-screen clip** and as a **looping motion background** behind text,
  rendered into the output via `AVPlayerLayer`.
- Transport: play / pause / **seek**, **loop** (`AVPlayerLooper`), **volume/mute**,
  **end behavior** (hold / black / auto-advance).
- **Pre-buffer the next clip** (`AVQueuePlayer`, `preferredForwardBufferDuration`,
  preroll); decode off the main thread; **graceful fallback** on bad files.
**Frameworks:** AVFoundation, AVKit.
**✓ Checkpoint (gate):** A full-length clip plays on the audience output **with no
stutter/glitch/audio drift**; the **next clip starts instantly** when triggered; a
corrupt file shows a placeholder instead of crashing.

## Phase 6 — Songs & text content  · M
**Goal:** Author the most common content type and run it.
**Build:**
- Song model: **sections** (Verse/Chorus/Bridge/Tag); **auto-split** long sections
  into slides by line count; section labels in grid/navigator.
- Manual entry editor for songs; sermon/text slides (title + body/bullets).
- A code-defined **default theme** so new content looks good without the editor.
**Frameworks:** SwiftUI, the Phase 2 renderer.
**✓ Checkpoint (gate):** Type a song's lyrics with section markers → slides generate and
look good → add it to a playlist → run it live from the keyboard.

## Phase 7 — Bible content  · M
**Goal:** Offline scripture lookup that auto-builds slides.
**Build:**
- Bundle **KJV + WEB** (the most common public-domain English Bibles), stored in
  **SQLite** (aligns with SwiftData) and built at packaging time from a public-domain
  dataset in a common open format (**OSIS / Zefania XML**); reference **parser**
  (`John 3:16-18`) on standard book/chapter/verse; **auto-split** passages.
- Reference (book/chapter/verse + translation) shown on slide.
**Frameworks:** Foundation; bundled Bible data.
**✓ Checkpoint (gate):** Enter `John 3:16-18` **offline** → correct passage split across
slides → run live. Settles MVP open questions on translations + data format.

## Phase 8 — Slide editor  · XL  *(critical screen)*
**Goal:** The WYSIWYG editor from `slide-editor-mac-native.html` and MVP §3.2.
**Build:**
- Canvas with select / **drag / resize** of text & image objects (handles), **zoom**
  (`MagnifyGesture`), **snap-to-grid**, **alignment guides**, **safe-area** overlay.
- Inspector: font, paragraph, **stroke/shadow**, **arrange** (position/size/layer),
  **background** (color/gradient/image/video), theme + **"set as default style."**
- **Undo/redo**. *(May back the canvas with an `NSView`/Core Animation layer tree if
  SwiftUI interaction precision is insufficient — evaluate during this phase.)*
**Frameworks:** SwiftUI (+ AppKit canvas if needed), Core Text/TextKit, the renderer.
**✓ Checkpoint (gate):** **A non-designer designs a good-looking slide from scratch in
under a minute**; edits persist and appear live; undo/redo is reliable.

## Phase 9 — Reliability hardening & dress rehearsal  · L  *(the real exam)*
**Goal:** Meet every MVP §5 success criterion under stress.
**Build:**
- Crash recovery (reopen exactly where left off); autosave robustness; missing-media
  placeholders everywhere; **fast cold launch**; pre-render upcoming slides.
- Stress/soak test: a full service with songs, Bible, video, display changes; profile
  CPU/GPU/memory and fix hotspots.
**Frameworks:** Instruments, XCTest/integration tests.
**✓ Checkpoint (gate):** A complete **dress-rehearsal service runs with zero
crashes/freezes and no visible lag**, including display unplug/replug — i.e. all of
MVP §5 demonstrably pass.

## Phase 10 — Packaging & release prep  · M
**Goal:** A build a volunteer can install and trust.
**Build:**
- App icon, code signing + **notarization**, first-run/onboarding, bundled sample
  content, crash reporting, update mechanism.
**Frameworks:** Xcode archive, notarytool.
**✓ Checkpoint (gate):** Signed, notarized build installs cleanly on a fresh Mac and a
non-technical user can run a service end-to-end without help.

---

## How to use these checkpoints

- Each gate is a **hard stop**: demo it (ideally on real hardware with a second display)
  and confirm the acceptance criteria before starting the next phase.
- Keep the **shared `SlideRenderer`** and **edit/live separation** invariant across all
  phases — they are what make the reliability promise hold.
- Phases 3 and 5 are the highest-risk; if either gate slips, stop and resolve it before
  building breadth — the product's value depends on them.

## Out of scope (post-MVP — see `docs/MVP.md` §6)
Stage display, reusable theme library, multiple outputs, lower thirds, NDI/Syphon,
imports, iPad remote, iCloud sync, CCLI/paid content, advanced video trimming.

## Decisions (locked · 2026-05-27)
1. **Minimum macOS:** **14 (Sonoma).**
2. **Persistence:** **SwiftData** (SQLite-backed).
3. **Bible:** bundle **KJV + WEB**, stored in **SQLite**, built from a public-domain
   dataset in a common open format (**OSIS / Zefania XML**); standard book/chapter/verse
   references.
4. **Video formats (MVP):** **.mp4 / .mov** (H.264 / HEVC), hardware-decoded via AVFoundation.
5. **Product name:** **Jerusalem** (confirmed).
