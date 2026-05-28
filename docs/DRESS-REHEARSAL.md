# Jerusalem — Dress-Rehearsal Checklist

This is the **hardware-side** of the Phase 9 gate. XCTest covers everything the
headless tests can reach (snap math, splitter rules, model round-trips, the
prewarmer's bounded LRU, navigation clamps). The list below is the rest — the
parts that need a real Mac, a real external display, and a real video file.

Run through it end to end on each release candidate. **Every "Expected" line
that doesn't hold is a Sunday-morning risk.**

Setup:

- Mac on the minimum supported macOS (14 Sonoma).
- A second display, HDMI or DisplayLink — whichever the host church uses.
- A folder of "real" sample content: 1–2 mp4 clips (≥ 60s), 1 motion-bg loop,
  1 PNG background, the bundled sample song, a Bible passage.
- Build the app once: `xcodegen generate && xcodebuild …`. No DerivedData
  shortcuts; pretend it's a first launch on a fresh machine.

---

## 1. First-launch cold start

1. Delete `~/Library/Application Support/Jerusalem` (or run the build under
   a new user account).
2. Launch the app.

**Expected**
- Operator window appears in ≤ 3 seconds on a current-gen Mac.
- Sample song (`Amazing Grace`) and starter Bible verses are seeded.
- Sidebar selection lands on the sample playlist.

**Fails if** — splash hangs, container errors in Console, sidebar is empty.

## 2. Reopen-where-you-left-off

1. Select a different item (e.g. the Bible item with `John 3:16-18`).
2. Quit the app (⌘Q).
3. Relaunch.

**Expected** — the same item is reselected; the slide grid shows its slides
without a "no selection" flash.

**Fails if** — selection resets to default, or `LastPosition` throws (check
Console).

## 3. External display attach

1. With the operator window open, plug in the second display.
2. Menu: *Start Output* → choose the external display.

**Expected**
- The audience window appears full-screen on the external display, borderless,
  black-fill.
- The operator window is unaffected (still keyboard-active).

**Fails if** — output window opens on the laptop screen, has window chrome,
or steals focus from the operator window.

## 4. Keyboard run-through

1. Select a song with ≥ 4 slides.
2. Press **Space** repeatedly.
3. Press **←** to step back.
4. Press **B** → **B** (toggle Black panic on / off).
5. Press **C** → **C** (Clear).
6. Press **L** → **L** (Logo).

**Expected**
- Each press updates the audience screen within one frame.
- Panic toggles round-trip cleanly back to the live slide.
- The slide grid's red LIVE badge stays in sync with the audience output.

**Fails if** — keys are ignored while the search box has focus is *expected*;
keys ignored *outside* the search box is a regression.

## 5. Video soak

1. Import a mp4 ≥ 60 seconds via *Add → Import Media…*.
2. Add it to the active playlist.
3. Press **Space** until the video item goes live.
4. Watch for ≥ 60 seconds.

**Expected**
- Playback is smooth — no stutter, no audio drift.
- Audio level matches the item's *Muted* / *Volume* settings.
- *End behavior* matches the inspector (hold / black / auto-advance).

**Fails if** — visible dropped frames, audio desync > 100 ms, or playback
fails silently to black.

## 6. Next-clip handoff

1. Add a second mp4 to the playlist immediately after the first.
2. With the first clip live, press **→** when it's near its end.

**Expected** — the second clip starts within ≤ 100 ms of the keypress, no
visible flash, no audio gap.

**Fails if** — there's a visible black frame between clips on the audience
display.

## 7. Motion background under text

1. Edit a slide: set a looping mp4 as `backgroundVideoFilename` (you can do
   this in-code or via the Inspector once gradient/background polish lands).
2. Go live on that slide.

**Expected**
- The video loops smoothly behind text.
- The text remains crisp; stroke/shadow legible against any frame of the
  background.

**Fails if** — the slide flickers between video frames and text re-draws.

## 8. Display unplug → replug

1. With the audience output running on the external display, **unplug** it.

**Expected**
- App does not crash.
- A `screensChanged` event fires; output reattaches to the laptop display
  as a preview window, or stays unmounted if no preferred screen exists.

2. **Replug** the external display.

**Expected** — the audience output returns to the external display without
manual restart.

**Fails if** — any of the above throws, hangs, or requires *Stop / Start
Output* to recover.

## 9. Missing media on a real playlist

1. Import a clip.
2. Delete the underlying file from `~/Library/Application Support/Jerusalem/Media`.
3. Reopen the app.

**Expected**
- The slide grid shows a yellow ⚠ on the affected slide.
- Going live on it falls back to black (video) or background color (image) —
  no crash.

**Fails if** — app crashes, or the slide shows a stale frame from the cache.

## 10. Editor round-trip

1. Right-click a slide in the grid → *Edit Slide…*.
2. Move + resize the text box, change font, change background color.
3. Close the sheet.

**Expected**
- Grid thumbnail updates immediately.
- Slide on the audience screen reflects edits if it's currently live.
- ⌘Z inside the editor reverses the last gesture.

**Fails if** — edits persist but thumbnails / audience output don't refresh.

### 10.1 Slide navigator (Phase 8.2.1)

1. Open the editor on an item with ≥ 3 slides.
2. Click a different thumbnail in the left rail.
3. Press the `+` button at the top of the rail.

**Expected** — the canvas swaps without closing the sheet; the new blank
slide appears in the rail and on the canvas, themed via the item's theme.

### 10.2 Status bar + toast + visible Undo/Redo (Phase 8.2.2)

1. Confirm the bottom status bar shows `● Autosaved · 16:9 · 1920×1080 px ·
   Snap to grid · Guides · Safe area · Zoom 100%`.
2. Drag a text element until its center hits 0.5.
3. Click the visible Undo button in the toolbar.

**Expected** — a "Snapped to center" capsule appears at the top and
disappears within ~1.1 s; Undo reverts the last drag in one step.

### 10.3 Inline text edit + aspect picker (Phase 8.2.3)

1. Double-click a selected text element on the canvas.
2. Type a new line, press Esc.
3. Toggle the toolbar's aspect picker from 16:9 to 4:3.

**Expected** — the field replaces the element in place; ⌘Z reverts the
commit as a single step; the canvas reshapes to 4:3 immediately.

### 10.4 Text styling depth (Phase 8.3.1)

1. Pick a text element. Set line spacing to ~2.0×, letter spacing to +6,
   stroke width to 8 with red color, shadow blur to 30.
2. Toggle the Justify alignment.
3. Toggle Underline.

**Expected** — every change is visible in the rendered output (grid
thumbnail + canvas + audience display if live). Justify wraps long lines
edge-to-edge; underline appears in the rasterized image.

### 10.5 Slide backgrounds (Phase 8.3.2)

1. Pick the Gradient type in the Background section, set a second color
   and an angle of 45°.
2. Switch to Image, choose a PNG.
3. Switch to Video, choose an mp4.

**Expected** — gradient draws corner-to-corner along the chosen angle;
image draws aspect-fill; video loops on the audience display.

### 10.6 Arrange + theme (Phase 8.3.3)

1. With 3 text elements on a slide, use the Front / Forward / Back /
   Send-to-Back row to reorder them.
2. Edit the X/Y/W/H percent fields (try `42.5%`).
3. Select an element with a custom font + color, then press *Set as default
   style for new slides*. Press *Add Text* on a fresh slide.

**Expected** — render order matches the button row; percent edits clamp to
0–100; the freshly added text uses the captured font + color.

## 11. Edit-vs-rebuild precedence

1. Open the song editor; the *Restore auto-generated slides* button must be
   hidden.
2. Open the slide editor for one slide → make any change → close.
3. Return to the song editor — change `linesPerSlide` from 2 to 3.

**Expected**
- The manually edited slide stays untouched.
- The *Restore auto-generated slides* button appears in the song editor's
  *Derived slides* section.
- Pressing it brings everything back to auto-derived.

## 12. The whole service

Run a complete mock service:

1. Open + arm a real playlist (intro loop video → opening song → Bible
   reading → sermon points → closing song → outro video).
2. Run it keyboard-only, from cold launch to last slide, with the audience
   output on the external display.
3. Mid-service, unplug + replug the display once.

**Expected** — zero crashes, zero visible lag, zero hangs from start to end.
This is the Phase 9 gate.
