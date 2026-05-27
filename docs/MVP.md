# Jerusalem — MVP Specification

> A native, Mac-only church presentation app.
> **The church presentation app that never lets you down on Sunday morning.**

| | |
|---|---|
| **Status** | Draft — MVP scope approved |
| **Platform** | macOS only, native Swift |
| **Last updated** | 2026-05-27 |
| **Scope** | "Lean Core" — the first shippable version |

---

## 1. Overview

Jerusalem is a presentation app for churches: it shows **song lyrics, Bible verses,
sermon points, and video** on a projector/TV during a live service, and gives the
user a **slide editor** to design how that content looks. The operator organizes
content into **playlists** and runs the service from a control window, advancing
slides with the **arrow keys or spacebar**.

The market leader (ProPresenter) is powerful but widely criticized for being slow,
heavy, and **prone to crashing or freezing mid-service**. Jerusalem's entire reason
to exist is to win on the opposite: **reliability and speed on a native Mac.**

### Primary differentiator
**Reliability & speed.** Every MVP decision is judged against one promise: *it works,
instantly and without fail, during a live Sunday service.* Features that threaten
that promise are deferred.

### Target user
A **volunteer or part-time operator** at a small-to-medium church, not a media
professional. They need to prepare slides during the week and run the service
confidently on Sunday, ideally without reading a manual.

---

## 2. Goals & non-goals

### Goals (MVP)
- Show songs, Bible verses, sermon/text slides, and video reliably on a second screen.
- Let a non-designer build good-looking slides in a simple editor.
- Play video smoothly — no stutter, glitches, or format surprises.
- Organize content into reusable playlists and run a service from the keyboard.
- Run an entire service with zero crashes or visible lag; launch fast and recover
  gracefully from interruptions.

### Non-goals (MVP — deferred to later phases)
Advanced video trimming (in/out points) · advanced media management · stage/confidence
display · reusable theme library · multiple outputs · lower thirds · NDI/Syphon ·
imports from other apps · iPad remote · iCloud sync · CCLI SongSelect / paid Bible
translations.

---

## 3. Feature set

### 3.1 Content types

**Songs / lyrics**
- Organized into **sections**: Verse 1, Verse 2, Chorus, Bridge, Tag, etc.
- Each section produces one or more slides (long sections auto-split by line count).
- Section labels are visible in the editor and slide grid for fast arranging.

**Bible verses**
- Bundled **public-domain translations** (e.g. KJV, WEB, ASV) — works fully offline,
  no licensing cost.
- **Reference lookup**: type `John 3:16-18` to fetch the passage.
- **Auto-split** long passages across multiple slides so text always fits.
- Reference (book, chapter, verse + translation) shown on the slide.

**Sermon points / text slides**
- Free-form title + body / bullet text.
- Used for sermon outlines, announcements, welcome screens.

**Video**
- Full-screen **video clips** triggered as their own item (bumper, sermon
  illustration, testimony, countdown), and looping **motion backgrounds** behind
  lyrics/text.
- Operator controls: **play / pause / seek** (scrub bar), **loop** toggle,
  **volume / mute**, and **end behavior** (hold last frame · go to black ·
  auto-advance to next item).
- Native, hardware-accelerated playback — see §3.5.

**Backgrounds**
- Solid color, gradient, static image, and **looping video (motion) background**.

### 3.2 Slide editor (basic WYSIWYG)

- **Canvas** at a fixed aspect ratio: **16:9** default, 4:3 selectable.
- Add, drag, resize **text boxes** and **images**.
- **Layer order**: background (color / gradient / image / **video**) → image → text
  (foreground).
- **Text styling**: font, size, color, alignment, line & letter spacing,
  **stroke/outline**, and **drop shadow** (essential for legibility over busy
  backgrounds).
- **Auto-fit** text to its box.
- **Snap-to-grid**, alignment guides, and a **safe-area overlay**.
- A **default theme** plus "set as default style" so new slides inherit a consistent
  look. *(A full reusable-template system → Phase 2.)*

### 3.3 Library & playlists

- **Library**: a searchable collection of all content — songs, presentations, Bible
  items, and **media (videos, images)**.
- **Media library**: import video and image files; shown with thumbnails (basic
  management — advanced organization is Phase 2).
- **Folders / tags** to organize the library.
- **Playlists**: multiple **named, saved, drag-to-reorder** playlists. Each is an
  ordered list of content for a service or purpose (e.g. "Sunday AM", "Christmas",
  "Youth"). A playlist set to loop doubles as a **pre-service loop** of images/video.

### 3.4 Live control & navigation

- **Operator window**: a slide grid for the live item + the active **playlist** in a
  sidebar.
- **Audience output window**: full-screen on the second display (auto-detected).
- **Navigation**:
  - **→ / ↓ / Spacebar** — next slide
  - **← / ↑** — previous slide
  - **Click** any slide thumbnail to go live immediately
- **Video transport** (when a clip or motion background is live): play / pause /
  seek, loop, volume / mute; the clip's **end behavior** runs automatically.
- **"Panic" hotkeys** (always available):
  - **Black** screen
  - **Clear** text (show background only)
  - **Logo / holding** slide
- **Transitions**: cut and **fade**. *(More transitions → Phase 2.)*
- **Search-and-go-live**: jump to any song or verse quickly.

### 3.5 Reliability foundations *(first-class MVP work, not polish)*

- **Edit/live separation**: editing must never stall or interrupt the audience
  output.
- **Autosave + crash recovery**: reopen exactly where the operator left off.
- **Fast cold launch**; pre-render upcoming slides so advancing is instant.
- **Graceful missing-media handling**: show a placeholder, never crash.
- **Reliable video**: hardware-accelerated decode (AVFoundation), **pre-buffer the
  next clip** before it goes live so playback starts instantly, decode off the render
  thread, and fall back gracefully on unsupported/corrupt files. This is the feature
  ProPresenter is most criticized for — it must be rock-solid here.
- **Stable full-screen output** across display sleep, resolution changes, and
  unplug/replug.

---

## 4. Key user flows

**Prepare a song (during the week)**
1. New Song → enter title and lyrics → mark section labels.
2. Pick/adjust the default theme → preview slides.
3. Save to library.

**Add a Bible passage**
1. New Bible item → choose translation → type reference (`Romans 8:28`).
2. App fetches and auto-splits the passage into slides.

**Add a video or motion background**
1. Import a video file into the media library.
2. Use it as a full-screen clip item, or set it as a slide's motion background.
3. Set loop, volume/mute, and end behavior.

**Build a playlist**
1. Create a playlist for Sunday → drag in songs, Bible items, sermon slides, video.
2. Reorder to match the run of service; save it (reuse or duplicate later).

**Run the service (Sunday)**
1. Connect projector → audience window goes full-screen automatically.
2. Select the first item → press **Spacebar / arrow keys** to advance.
3. Use **Black / Clear / Logo** between segments as needed.

---

## 5. Success criteria

- An operator can build a song, look up a Bible passage, arrange a **playlist**, and
  run a full service **using only the keyboard** — without reading a manual.
- The audience output runs an entire service with **zero crashes or freezes** and no
  visible lag, including display unplug/replug.
- A full-length **video plays without stutter, glitch, or audio drift**, and the next
  clip starts instantly when triggered.
- A non-designer can produce a good-looking slide in **under a minute**.
- **Launch-to-ready in a few seconds** on typical church Mac hardware.

---

## 6. Roadmap beyond MVP (for context)

- **Phase 2 — Media & confidence**: advanced video (in/out trim points), advanced
  media management, stage display, reusable themes, countdown/announcement slides.
- **Phase 3 — Switchers & reach**: imports (ProPresenter/OpenSong/OpenLyrics/Zefania
  XML/plain text), multiple outputs, lower thirds, iPad remote, iCloud sync.
- **Phase 4 — Pro / production**: NDI/Syphon, macros, MIDI/DMX, streaming hooks,
  Planning Center, CCLI SongSelect, dual-language lyrics.

---

## 7. Decisions (locked · 2026-05-27)

- **Product name:** Jerusalem (confirmed — the product name, not a codename).
- **UI direction:** Prototype C (Mac Native) + the Mac-native slide editor.
- **Minimum macOS:** 14 (Sonoma).
- **Persistence:** SwiftData (SQLite-backed).
- **Bible:** bundle KJV + WEB (public domain), stored in SQLite, built from a common
  open format (OSIS / Zefania XML); standard book/chapter/verse references.
- **Video formats (MVP):** .mp4 and .mov containers (H.264 / HEVC), hardware-decoded
  via AVFoundation.

*Next step after sign-off: a separate **technical architecture** document
(app structure, render pipeline, data model & persistence, dual-window output,
Bible data format).*
