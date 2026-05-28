# Phase 8 Part 2 — Slide editor: closing the prototype gap

## Context

Phase 8 Part 1 landed the *mechanical* core of the slide editor: snap / clamp
/ drag math (`SlideGeometry`), 8-handle resize, `ModelContext.undoManager`
undo, `Slide.isManuallyEdited` rebuilder yield, and the
image-`SlideElement` renderer fix. That covers the invariants the rest of
the app depends on, but as a complete editor surface it's roughly **a third**
of what `docs/prototypes/mvp/slide-editor-mac-native.html` specifies — which
in turn is a near-1:1 rendering of **MVP §3.2**. So before Phase 10
packaging, Phase 8 isn't honestly done.

Part 2 closes that gap. To keep changes reviewable on real hardware, it's
split into **six small phases**, each with a runnable, demonstrable gate.
Each gate is a **hard stop**: demo it (ideally on a Mac with an external
display, per `docs/DRESS-REHEARSAL.md`) and confirm the acceptance criteria
before starting the next phase.

The Part-1 math (snap/clamp/drag, manual-edit yield, undo, image-element
renderer fix) **stays unchanged** — Part 2 is additive structure + view +
typography work, not a rewrite.

> Sizes are relative effort (S / M / L), not calendar estimates.

---

## Decisions (locked — call these out so they're not re-debated)

1. **Editor stays a sheet**, not a separate window. The prototype mockup's
   window chrome is a Figma-style render, not a UX constraint.
2. **Aspect ratio is per-item**, not per-slide. MVP §3.2 doesn't specify
   granularity; per-item avoids mixing aspects within one program.
3. **"Set as default style for new slides" writes to `Item.theme`** (creates
   one if nil), not to an app-wide global. App-wide theme library is a
   Phase-2 / §6 concept.
4. **No Shape tool** in Phase 8. The prototype's toolbar has one but MVP §3.2
   doesn't list shapes.
5. **Any inspector or canvas edit bumps `Slide.isManuallyEdited`**. The
   existing *Restore auto-generated slides* button on the content editors
   covers the recovery path.

---

# Tier 1 — Editor shell (Phases 8.2.1 → 8.2.3)

Pure view + small-state work. No model schema changes, no renderer changes.
Three small phases bring the editor's *layout and UX cues* up to the
prototype.

## Phase 8.2.1 — Slide navigator · S/M

**Goal:** The editor stops being a one-slide modal and becomes a multi-slide
canvas with a navigator rail.

**Build:**
- `SlideNavigatorView` (new) — left rail listing the parent item's
  `orderedSlides`. Each row: numeric index + a small `RenderableSlideView`
  thumbnail + the slide's `sectionLabel`. Selection mirrors the editor's
  currently-edited `Slide`.
- Header `+` button inserts a fresh blank `Slide` at the bottom, themed via
  `Item.theme ?? Theme.makeDefault()`, and selects it.
- `SlideEditorView` restructured to a 3-pane `HSplitView`
  (navigator | stage | inspector); the stage stays the existing canvas.
- `OperatorView` passes the parent `Item` into the editor sheet so the
  navigator can list siblings.

**Frameworks:** SwiftUI (`HSplitView`, `List`), the shared `RenderableSlideView`.

**✓ Checkpoint (gate):** Open the editor for any slide of an item with ≥ 3
slides → the navigator shows all of them in order → clicking a different
thumbnail swaps the editor's target without closing the sheet → pressing `+`
inserts a blank slide that appears in the navigator and on the canvas, with
the item's theme styling applied.

---

## Phase 8.2.2 — Status bar + toast + visible Undo/Redo · S

**Goal:** Surface autosave + canvas info + snap-feedback the way the
prototype centers them.

**Build:**
- `SlideStatusBar` (new) — bottom bar inside the editor sheet:
  `● Autosaved · {aspect} · {pixel size} · Snap to grid · Guides ·
  Safe area · Zoom {%}`. Snap / Guides / Safe-area toggles relocate *here*
  from the toolbar; zoom slider stays in the toolbar but its current value
  mirrors in the status bar.
- `EditorToast` (new) — small top-center capsule that flashes a message
  ("Snapped to center", "Snapped to edge") for ~1 s.
  `SlideCanvasView` calls it from its existing `snapVertical` /
  `snapHorizontal` match branches.
- Toolbar polish: visible `arrow.uturn.backward` / `arrow.uturn.forward`
  buttons next to the add/duplicate/delete cluster, bound to
  `modelContext.undoManager.undo()` / `.redo()` (mirrors the existing
  ⌘Z / ⇧⌘Z shortcuts).
- Selection handle styling: filled white + 1.5pt accent stroke, 4×4-corner
  radius; canvas backdrop gains a checker-dot desk via SwiftUI `Canvas` +
  radial-gradient stride (matches the prototype's `.stage`).

**Frameworks:** SwiftUI, `Canvas` for the dot pattern, existing
`SlideGeometry` snap branches as the toast trigger.

**✓ Checkpoint (gate):** Editor opens with a bottom status bar (snap /
guides / safe-area toggles operate from there) and a desk-dot backdrop;
visible Undo/Redo buttons in the toolbar do what ⌘Z / ⇧⌘Z already do; drag
a text element so its centerX hits 0.5 → "Snapped to center" toast appears
and disappears within 1.1 s. Resize handles look like the prototype.

---

## Phase 8.2.3 — Inline text edit + aspect picker · S/M

**Goal:** Direct manipulation of text (the prototype's `contenteditable`)
and a 16:9 / 4:3 switch on the editor toolbar.

**Build:**
- `InlineTextEditOverlay` (new) — double-clicking a selected text element
  overlays a multi-line SwiftUI `TextField` (or `TextEditor` for >1 line)
  positioned at the element's frame; commits on Esc, return, or focus
  loss; cancel-on-Esc restores the previous text. Updates funnel through
  `ModelContext.undoManager` so ⌘Z reverts the commit as one undo step.
- `Item.aspectRatio: String?` (`"16:9"` default, `"4:3"` selectable). The
  canvas's `GeometryReader` reads it and supplies the right ratio to
  `RenderableSlideView`, which already accepts an `aspectRatio` param.
- Editor toolbar: a `Picker(selection:)` for aspect — `Item.aspectRatio`
  binding.
- Bookkeeping: any commit bumps `Slide.isManuallyEdited`.

**Frameworks:** SwiftUI (`TextEditor`, `FocusState`,
`onSubmit`), the existing aspect-ratio param of `RenderableSlideView`.

**✓ Checkpoint (gate):** Double-click a text element on the canvas → an
inline field replaces the text → type new text → press Esc → element
updates; ⌘Z reverts to the previous text. Toggling the toolbar picker
between 16:9 and 4:3 changes the canvas frame shape (audience-output
follow-through arrives in Phase 8.3.x when the renderer reads the field).

---

# Tier 2 — Typography, background, theme (Phases 8.3.1 → 8.3.3)

Model + renderer + inspector restructure. Each phase ships **one** complete
section of the inspector working end to end.

## Phase 8.3.1 — Text styling depth · M

**Goal:** Line spacing, letter spacing, stroke width, shadow blur (and the
matching colors / offsets), underline, and justify alignment — all
adjustable from the inspector and faithfully rendered.

**Build:**
- Model additions on `SlideElement`:
  - `lineSpacingMultiplier: Double = 1.35`
  - `letterSpacing: Double = 0`
  - `strokeWidth: Double = 3.0`
  - `strokeColorHex: String = "#000000"`
  - `shadowBlur: Double = 12`
  - `shadowOffsetY: Double = -4`
  - `shadowColorHex: String = "#000000B3"`
  - `isUnderlined: Bool = false`
- `TextAlignmentOption.justified` (new case; renderer maps to
  `NSTextAlignment.justified`).
- `RenderableElement` extended with all of the above; the snapshot init
  copies from the model.
- `SlideRenderer` applies them via `NSAttributedString` keys:
  - `.kern` ← `letterSpacing`
  - `NSMutableParagraphStyle.lineSpacing` ← derived from
    `lineSpacingMultiplier`
  - `.strokeWidth` ← `strokeWidth` (negative for fill + stroke), `.strokeColor`
    ← `strokeColorHex`
  - `NSShadow.shadowBlurRadius` ← `shadowBlur`, `.shadowColor`
    ← `shadowColorHex`, `.shadowOffset.height` ← `shadowOffsetY`
  - `.underlineStyle` when `isUnderlined`
- Inspector restructure (`SlideInspectorView`):
  - **Font** section: family · size stepper *inline with* a color chip ·
    B/I/U button group.
  - **Paragraph** section: 4-way alignment (left / center / right / **justify**)
    · line-spacing slider · letter-spacing slider · autofit toggle.
  - **Stroke & Shadow** section: stroke toggle + color chip + width slider;
    shadow toggle + color chip + blur slider.

**Frameworks:** SwiftUI, Core Text / TextKit (via `NSAttributedString`).

**✓ Checkpoint (gate):** A text element rendered with custom line-spacing,
letter-spacing, stroke width, and shadow blur produces a measurably different
`CGImage` than the default (sample pixels for stroke extension + shadow blur
radius). Justify alignment round-trips through the renderable snapshot.
Underline appears in the rasterized output.

---

## Phase 8.3.2 — Slide backgrounds · M

**Goal:** The four background types — color, gradient, image, video — work
from the inspector and render correctly.

**Build:**
- Model on `Slide`:
  - `backgroundKindRaw: String` + computed `backgroundKind:
    SlideBackgroundKind { color, gradient, image, video }` accessor (project
    convention).
  - `gradientHex2: String?` (second color)
  - `gradientAngle: Double = 135` (degrees, 0 = left→right)
- `RenderableSlide` carries the new fields.
- `SlideRenderer` gains a gradient-fill branch when
  `backgroundKind == .gradient`: build a `CGGradient` between
  `backgroundColorHex` and `gradientHex2`, draw with
  `CGContext.drawLinearGradient` along `gradientAngle`. Existing
  image / video background paths stay, gated by `backgroundKind`.
- Inspector **Background (slide)** section:
  - Type segmented control (Color / Gradient / Image / Video).
  - Swatches grid — a curated 4-swatch palette plus a "More…"
    `ColorPicker`.
  - Image / Video pickers open `NSOpenPanel` and write
    `slide.backgroundImageFilename` / `…VideoFilename` via existing
    `MediaStorage.importFile(at:)`.
  - Gradient mode shows a second `ColorPicker` for `gradientHex2` and an
    angle stepper.

**Frameworks:** SwiftUI, Core Graphics (`CGGradient`), AppKit (`NSOpenPanel`),
existing `MediaStorage`.

**✓ Checkpoint (gate):** Picking *Gradient* draws a two-color linear gradient
(verify by sampling pixels at top vs bottom of the rendered output). Picking
*Image* and choosing a PNG sets the slide's background image and the
renderer draws it aspect-fill. Picking *Video* sets a looping motion
background that plays on the audience output.

---

## Phase 8.3.3 — Arrange + theme actions · S/M

**Goal:** The Arrange section's X/Y/W/H grid and Front/Forward/Back row
match the prototype; the Theme section persists a "set as default style"
for the item.

**Build:**
- Pure helpers on `SlideGeometry`: `movedToFront(_:in:)` and
  `movedToBack(_:in:)` mirroring `raised` / `lowered`.
- Inspector **Arrange** section:
  - 2×2 mini-input grid for X / Y / W / H — TextFields parsing percent
    strings (`"42.5%"`) and binding through `SlideGeometry.clamped`.
  - Front / Forward / Back / Send-to-Back button row, wired to the four
    geometry helpers, mutating element `order` on the slide.
- Inspector **Theme** section:
  - Theme preview swatch (a small `RenderableSlideView` of a stub slide
    styled with the item's theme defaults).
  - Theme name + a `Change…` link that opens a sheet listing built-in
    themes (`Theme.makeDefault()` as the bootstrap option; future themes
    are out of scope per the locked Phase-2 decision).
  - A primary link **"Set as default style for new slides"** that copies the
    currently selected element's typography (`fontName`, `fontSize`,
    `colorHex`, `alignment`, `isBold`, `isItalic`, `hasShadow`,
    `hasStroke`, autofit, plus the new Phase 8.3.1 fields) back into
    `item.theme` (creating a `Theme` if missing).
- New helper `Theme.copy(from: SlideElement)` in
  `Sources/Jerusalem/Content/DefaultTheme.swift`.

**Frameworks:** SwiftUI, the existing `Theme` model + `apply(to:)` helpers.

**✓ Checkpoint (gate):** Three text elements on one slide can be reordered
via Front / Forward / Back / Send-to-Back and the rendered output's draw
order matches. The X/Y/W/H grid edits flow through `clamped`. Selecting an
element with a custom font + color, pressing *Set as default style*, then
*Add Text* on a new slide produces a fresh element that already carries
that font + color.

---

## How to use these checkpoints

- Each gate is a **hard stop** — demo it before starting the next phase.
- The Tier 1 phases (8.2.x) are pure view work; the Tier 2 phases (8.3.x)
  add model + renderer fields. **Run the Phase 1 persistence gate
  (`PersistenceTests`)** after each Tier-2 phase to catch schema
  regressions early.
- Append a row to `docs/DRESS-REHEARSAL.md` §10 for each phase's gate so
  the Phase-9 hardware checklist tracks Phase-8 polish too.

## Out of scope (deferred — not gate-critical)

- The **Shape tool** from the prototype toolbar (not in MVP §3.2).
- Real **font enumeration** — the inspector's family picker still hardcodes
  the six common families; driving from `NSFontManager` is polish.
- **Traffic-light window chrome** — the sheet form is fine; the prototype's
  chrome is a Figma render, not a constraint.
- **Multi-select + copy/paste** of elements — useful, but not in MVP §3.2.
- **Animated transitions** between slides in the editor preview — Phase 2
  feature per `docs/MVP.md` §6.
- **App-wide theme library** with reusable named themes — Phase 2 per §6.
- **AppKit / Core Animation canvas** — still on the table behind the same
  `SlideCanvasView` interface if SwiftUI gesture precision turns out to be
  insufficient on real hardware (per the original Phase 8 plan note).
