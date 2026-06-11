# Code Map — Jerusalem

A guided index to every source file in this project. **Each `.swift` file has a matching
`.md` explainer sitting right beside it** (e.g. `Item.swift` → `Item.md`), written for a
developer who knows JavaScript/TypeScript but is new to Swift. This page links them all,
grouped by folder, so you have one place to browse from.

> New to the codebase? Read [`CLAUDE.md`](CLAUDE.md) for the architecture rules and
> [`ARCHITECTURE.md`](ARCHITECTURE.md) for visual diagrams of how the app works, then
> follow the **Suggested reading order** below.

## Suggested reading order

If you're learning the app from scratch, this path goes from "what data exists" → "how it
becomes slides" → "how slides are drawn" → "how it goes live" → "the UI on top":

1. **The data** — [`Item`](Sources/Jerusalem/Models/Item.md), [`Slide`](Sources/Jerusalem/Models/Slide.md), [`SlideElement`](Sources/Jerusalem/Models/SlideElement.md)
2. **Authoring → slides** — [`ContentRebuilder`](Sources/Jerusalem/Content/ContentRebuilder.md), [`SlideSplitter`](Sources/Jerusalem/Content/SlideSplitter.md)
3. **Drawing** — [`RenderableSlide`](Sources/Jerusalem/Rendering/RenderableSlide.md), [`SlideRenderer`](Sources/Jerusalem/Rendering/SlideRenderer.md), [`SlideView`](Sources/Jerusalem/Rendering/SlideView.md)
4. **Going live** — [`LiveState`](Sources/Jerusalem/Live/LiveState.md), [`OutputController`](Sources/Jerusalem/Live/OutputController.md)
5. **The control surface** — [`JerusalemApp`](Sources/Jerusalem/JerusalemApp.md), [`OperatorView`](Sources/Jerusalem/Views/OperatorView.md)
6. **The slide editor** — [`SlideEditorView`](Sources/Jerusalem/Editor/SlideEditorView.md), [`SlideCanvasView`](Sources/Jerusalem/Editor/SlideCanvasView.md), [`SlideGeometry`](Sources/Jerusalem/Editor/SlideGeometry.md)

The four cross-cutting **invariants** that keep the "never fail on Sunday" promise — one
shared renderer, value-snapshot edit/live separation, normalized 0…1 coordinates, and
AppKit-owned output — are explained in the relevant docs above and in `CLAUDE.md`.

---

## App entry

| File | What it does |
| --- | --- |
| [`JerusalemApp.swift`](Sources/Jerusalem/JerusalemApp.md) | The app's entry point: declares the app's windows (operator window + dedicated slide-editor window) and wires up the shared state and database. |

## Models — the data (`Sources/Jerusalem/Models/`)

| File | What it does |
| --- | --- |
| [`Item.swift`](Sources/Jerusalem/Models/Item.md) | The top-level library entry — a song, Bible passage, text/sermon, or media clip — plus the ordered slides it produces. |
| [`Slide.swift`](Sources/Jerusalem/Models/Slide.md) | One projected page belonging to an `Item` — its background plus the ordered visual elements drawn on top. |
| [`SlideElement.swift`](Sources/Jerusalem/Models/SlideElement.md) | A single positioned thing on a slide — styled text, an image, or a vector shape — with its frame stored in resolution-independent normalized coordinates. |
| [`SongSection.swift`](Sources/Jerusalem/Models/SongSection.md) | A block of raw lyrics (verse, chorus, bridge, tag) belonging to a song — the authored source of truth that slides are derived from. |
| [`Playlist.swift`](Sources/Jerusalem/Models/Playlist.md) | A named, ordered set of items for a service — plus the `PlaylistEntry` join model that gives each item its position within that playlist. |
| [`Theme.swift`](Sources/Jerusalem/Models/Theme.md) | A reusable bundle of default visual styling (background color, font, text styling) that can be applied to slides. |
| [`BibleVerse.swift`](Sources/Jerusalem/Models/BibleVerse.md) | One database row representing a single Bible verse in a single translation (e.g. "John 3:16" in KJV). |

## Persistence — the database (`Sources/Jerusalem/Persistence/`)

| File | What it does |
| --- | --- |
| [`Persistence.swift`](Sources/Jerusalem/Persistence/Persistence.md) | Central SwiftData setup: declares the schema and builds the shared, autosaving, on-disk database container the whole app uses. |
| [`SampleData.swift`](Sources/Jerusalem/Persistence/SampleData.md) | Seeds a single sample song ("Amazing Grace") and a playlist into an empty store on first launch, so the app opens with something to look at. |
| [`BibleSeeder.swift`](Sources/Jerusalem/Persistence/BibleSeeder.md) | A one-shot loader that reads bundled Bible verses from JSON and inserts them into the SwiftData store so scripture can be looked up offline. |
| [`LastPosition.swift`](Sources/Jerusalem/Persistence/LastPosition.md) | Persists which item or playlist the operator had selected when the app last closed, so it reopens on the same selection. |

## Content — authoring → slides (`Sources/Jerusalem/Content/`)

| File | What it does |
| --- | --- |
| [`ContentRebuilder.swift`](Sources/Jerusalem/Content/ContentRebuilder.md) | The orchestrator that turns an item's *authored* content (song lyrics, sermon body, or Bible reference) into the actual `Slide` + `SlideElement` rows the renderer projects. |
| [`SlideSplitter.swift`](Sources/Jerusalem/Content/SlideSplitter.md) | Pure, unit-tested rules that chop authored content — song sections, Bible verses, sermon bodies — into slide-sized `SlideDraft` chunks. |
| [`SongLyricsParser.swift`](Sources/Jerusalem/Content/SongLyricsParser.md) | Parses a free-typed lyrics block (with `[Verse 1]` / `[Chorus]` markers) into ordered `ParsedSongSection` values — and serializes them back. |
| [`BibleReferenceParser.swift`](Sources/Jerusalem/Content/BibleReferenceParser.md) | Turns a free-typed string like `"John 3:16-18"` into a structured `BibleReference` value (book, chapter, verse range), or `nil` if it's malformed. |
| [`BibleBookCatalog.swift`](Sources/Jerusalem/Content/BibleBookCatalog.md) | The canonical list of all 66 Bible books, with an alias table that resolves messy user input ("1cor", "gen.", "PSALM") to a clean canonical name. |
| [`BibleStore.swift`](Sources/Jerusalem/Content/BibleStore.md) | The read-only query layer over the offline `BibleVerse` rows: given a parsed reference and a translation, it fetches the matching verses from SwiftData. |
| [`DefaultTheme.swift`](Sources/Jerusalem/Content/DefaultTheme.md) | Defines the built-in "Default Dark" look and the helpers that copy a `Theme`'s style onto freshly created slides/elements (and back). |

## Rendering — drawing slides (`Sources/Jerusalem/Rendering/`)

| File | What it does |
| --- | --- |
| [`SlideRenderer.swift`](Sources/Jerusalem/Rendering/SlideRenderer.md) | The single, shared function that turns a slide snapshot into a bitmap image — the one rendering path behind thumbnails, the inspector preview, and the live audience screen. |
| [`RenderableSlide.swift`](Sources/Jerusalem/Rendering/RenderableSlide.md) | Immutable value-type snapshots of a slide and its elements — the only data shape the renderer and live output are allowed to touch. |
| [`SlideView.swift`](Sources/Jerusalem/Rendering/SlideView.md) | The SwiftUI views that display a rendered slide on screen, re-rendering only when the content or pixel size actually changes. |
| [`SlidePrewarmer.swift`](Sources/Jerusalem/Rendering/SlidePrewarmer.md) | A bounded LRU cache that pre-renders upcoming slides so advancing the live output is instant instead of waiting on the renderer. |

## Live — the audience output (`Sources/Jerusalem/Live/`)

| File | What it does |
| --- | --- |
| [`LiveState.swift`](Sources/Jerusalem/Live/LiveState.md) | The single source of truth for what the audience currently sees and which slide is "live" — held as immutable value snapshots, never live database models. |
| [`OutputController.swift`](Sources/Jerusalem/Live/OutputController.md) | Owns the real macOS window that the audience sees, picks the right physical display, and keeps the output alive when displays are unplugged or change resolution. |
| [`OutputView.swift`](Sources/Jerusalem/Live/OutputView.md) | The SwiftUI view inside the audience window — reads `LiveState.content` and draws the right thing (slide, video, logo, or black) full-bleed with an optional fade. |
| [`VideoPlayerView.swift`](Sources/Jerusalem/Live/VideoPlayerView.md) | A SwiftUI wrapper around AVFoundation video playback for the audience output — hardware-decoded, looping or one-shot, engineered to fall back to black rather than ever crash. |
| [`VideoPrewarmer.swift`](Sources/Jerusalem/Live/VideoPrewarmer.md) | A global singleton that pre-loads the *next* video clip's asset (bounded LRU cache) so playback starts quickly when the operator switches to it. |

## Media (`Sources/Jerusalem/Media/`)

| File | What it does |
| --- | --- |
| [`MediaLibrary.swift`](Sources/Jerusalem/Media/MediaLibrary.md) | Two pure namespaces: `MediaImport` decides whether a file is a video or image by extension, and `MediaStorage` manages copying imported media into the app's on-disk media folder. |
| [`MediaAudit.swift`](Sources/Jerusalem/Media/MediaAudit.md) | A pure namespace of functions that scan for missing media files on disk, so the slide grid can show a "missing file" badge *before* it becomes a Sunday-morning surprise. |
| [`VideoCue.swift`](Sources/Jerusalem/Media/VideoCue.md) | An immutable value type describing a video clip to play on the output (file URL + loop / mute / end behavior) — safe to live inside `LiveState`'s snapshot because it's a copied value, not a live model. |

## Editor — the slide editor (`Sources/Jerusalem/Editor/`)

| File | What it does |
| --- | --- |
| [`SlideEditorWindowRoot.swift`](Sources/Jerusalem/Editor/SlideEditorWindowRoot.md) | The root view of the dedicated slide-editor window: takes an *item's* ID, re-resolves the live `Item`, hosts `SlideEditorView`, and tells the operator window to re-arm the live program when the editor closes. |
| [`SlideEditorView.swift`](Sources/Jerusalem/Editor/SlideEditorView.md) | The main editor screen: a three-pane composition (`content rail │ canvas │ inspector`) for authoring content, designing slides on a zoomable WYSIWYG canvas, and tweaking per-element properties — all editing the live model with undo. |
| [`SlideCanvasView.swift`](Sources/Jerusalem/Editor/SlideCanvasView.md) | The interactive WYSIWYG editing stage: renders the slide, overlays selection handles + alignment guides, and translates drags/resizes into normalized 0…1 mutations on the live model. |
| [`SlideGeometry.swift`](Sources/Jerusalem/Editor/SlideGeometry.md) | A namespace of pure, unit-testable geometry functions (snap, clamp, alignment guides, drag/resize, layer reorder) that power the editor canvas — all in normalized 0…1 coordinates, no UI. |
| [`SlideNavigatorView.swift`](Sources/Jerusalem/Editor/SlideNavigatorView.md) | The editor's left-rail slide picker: a `+`-to-add list of the item's slides, each a numbered thumbnail with its section label, two-way bound to the currently-edited slide. |
| [`SlideInspectorView.swift`](Sources/Jerusalem/Editor/SlideInspectorView.md) | The right-hand inspector panel: a tabbed container (Format / Arrange / Slide) hosting per-element styling and slide-wide settings, where every edit two-way-binds a model property and flips `isManuallyEdited`. |
| [`InspectorTab.swift`](Sources/Jerusalem/Editor/InspectorTab.md) | A small enum naming the three inspector tabs (Format / Arrange / Slide) and the pure rule for which tab to auto-focus when the canvas selection changes. |
| [`InspectorSection.swift`](Sources/Jerusalem/Editor/InspectorSection.md) | Three reusable inspector building blocks: a titled section container, a label-left/control-right row, and the header chip that names the selected object's type. |
| [`SlideArrangeSection.swift`](Sources/Jerusalem/Editor/SlideArrangeSection.md) | The inspector's "Arrange" section: a 2×2 grid of percent fields for X/Y/W/H plus a Front/Forward/Back/Send-to-Back button row, editing the selected element's frame and z-order. |
| [`SlideBackgroundSection.swift`](Sources/Jerusalem/Editor/SlideBackgroundSection.md) | The inspector's "Background (slide)" section: pick the background kind (color / gradient / image / video) and edit only the relevant controls, including a swatch palette and file pickers. |
| [`SlideThemeSection.swift`](Sources/Jerusalem/Editor/SlideThemeSection.md) | The inspector's "Theme" section: a preview swatch, theme name, a (stubbed) Change… picker, and a "Set as default style for new slides" button. |
| [`SlideLayersSection.swift`](Sources/Jerusalem/Editor/SlideLayersSection.md) | The left-rail "Layers" panel: a draggable, front-at-top list of the slide's objects where drag restacks z-order and trash/Delete removes an object. Plus the pure z-order math it uses. |
| [`InlineTextEditOverlay.swift`](Sources/Jerusalem/Editor/InlineTextEditOverlay.md) | A floating text editor positioned directly over a text element on the canvas, for editing slide text in place; commits on Enter/focus-loss, cancels on Escape. |
| [`EditorChrome.swift`](Sources/Jerusalem/Editor/EditorChrome.md) | Reusable visual chrome for the editor: the bottom status bar, the snap-feedback toast (plus its controller), and the dotted desk backdrop behind the stage. |
| [`ZoomBar.swift`](Sources/Jerusalem/Editor/ZoomBar.md) | The canvas's bottom-left zoom control (a `− NN% +` capsule) plus `CanvasZoomMath`, the single shared source of zoom bounds that buttons, pinch, and ⌘-scroll all funnel through. |

## Views — the operator window (`Sources/Jerusalem/Views/`)

| File | What it does |
| --- | --- |
| [`OperatorView.swift`](Sources/Jerusalem/Views/OperatorView.md) | The top-level operator (live-control) window — the control surface used live on Sunday morning to drive what's on the audience screen. |
| [`SidebarView.swift`](Sources/Jerusalem/Views/SidebarView.md) | The operator window's source list: a search-filtered Library on top, and a Playlists area below (names on the left, the selected playlist's items on the right). |
| [`SlideGridView.swift`](Sources/Jerusalem/Views/SlideGridView.md) | The operator's main detail grid: rendered thumbnails of the active program's slides — click to go live, right-click to edit. |
| [`PlaylistSlidesView.swift`](Sources/Jerusalem/Views/PlaylistSlidesView.md) | The operator's detail pane when a playlist is selected: every slide in the playlist, in running order, grouped under a sticky header per item. |
| [`PlaylistContentPane.swift`](Sources/Jerusalem/Views/PlaylistContentPane.md) | The right half of the sidebar's Playlists split: rename the selected playlist and add / reorder / remove its items. |
| [`InspectorView.swift`](Sources/Jerusalem/Views/InspectorView.md) | The operator window's trailing inspector: a live-output mirror (current + next), panic controls, the transition picker, and selected-item metadata. |
| [`SongEditorView.swift`](Sources/Jerusalem/Views/SongEditorView.md) | Phase 6 song editor: type lyrics with `[Verse 1]` / `[Chorus]` markers, set lines-per-slide, and watch the slide grid regenerate. |
| [`SermonEditorView.swift`](Sources/Jerusalem/Views/SermonEditorView.md) | Phase 6 editor for sermon/text items: a title plus body paragraphs that become point slides, split by blank lines and by lines-per-slide. |
| [`BibleEditorView.swift`](Sources/Jerusalem/Views/BibleEditorView.md) | Phase 7 Bible editor: type a scripture reference, pick a translation, and watch the slides regenerate from the bundled scripture store. |

## Support — small pure helpers (`Sources/Jerusalem/Support/`)

| File | What it does |
| --- | --- |
| [`ColorHex.swift`](Sources/Jerusalem/Support/ColorHex.md) | Two-way conversion between hex strings (`#RRGGBB[AA]`) and Apple's color types, with graceful fallbacks so a bad string never makes a color disappear. |
| [`LibrarySearch.swift`](Sources/Jerusalem/Support/LibrarySearch.md) | A tiny pure-function namespace that decides whether a search query matches a piece of text — token-by-token, case-insensitive, order-independent. |
| [`PlaylistEditing.swift`](Sources/Jerusalem/Support/PlaylistEditing.md) | A pure namespace of playlist "math" — assigning order numbers, reordering, removing entries, and naming new playlists — kept free of UI so it can be unit-tested. |

## Tools (`Tools/`)

| File | What it does |
| --- | --- |
| [`build-bible-db/main.swift`](Tools/build-bible-db/main.md) | A standalone Swift command-line tool that converts one or more OSIS XML Bible exports into the single JSON file (`bible-starter.json`) that `BibleSeeder` reads on first launch. |

## Tests (`Tests/JerusalemTests/`)

Tests are organized as **phase gates** — each one proves a milestone works headlessly.
Hardware-dependent behavior (real full-screen output, AVFoundation smoothness, display
unplug/replug) is verified by hand, not here.

| File | Phase | What it verifies |
| --- | --- | --- |
| [`AppSmokeTests.swift`](Tests/JerusalemTests/AppSmokeTests.md) | 0 | A bare-minimum "does the test target build and link against the app?" heartbeat. |
| [`PersistenceTests.swift`](Tests/JerusalemTests/PersistenceTests.md) | 1 | Songs, slides, and playlists fully save and restore across a container reopen; sample seeding happens exactly once. |
| [`SlideRenderingTests.swift`](Tests/JerusalemTests/SlideRenderingTests.md) | 2 | The one shared `SlideRenderer` produces an image at the requested size, auto-fits text, draws glyphs, and honors each background kind. |
| [`LiveOutputTests.swift`](Tests/JerusalemTests/LiveOutputTests.md) | 3 | Live content is an immutable snapshot (editing the model can't change the screen), and `ScreenSelection.outputIndex` picks the right display. |
| [`LiveNavigationTests.swift`](Tests/JerusalemTests/LiveNavigationTests.md) | 4 | The operator can run a program entirely by keyboard — arm, next/previous (clamped), go-live-by-id, Black/Clear panic — plus library search. |
| [`MediaTests.swift`](Tests/JerusalemTests/MediaTests.md) | 5 | File-type rules, importing media onto disk, turning a media `Item` into the right program slide, and the video pre-warmer's caching. |
| [`SongContentTests.swift`](Tests/JerusalemTests/SongContentTests.md) | 6 | A `[Verse 1]`/`[Chorus]` text block parses, splits into labeled slides, rebuilds through the in-app path, and runs end-to-end as a live program. |
| [`BibleTests.swift`](Tests/JerusalemTests/BibleTests.md) | 7 | The whole offline Bible pipeline — catalog, parser, store, splitter — culminating in `John 3:16-18` producing three navigable slides. |
| [`SlideShapeTests.swift`](Tests/JerusalemTests/SlideShapeTests.md) | 8.4 | The new `shape` element round-trips through the snapshot, rasterizes through the shared renderer, and persists across contexts. |
| [`SlideEditorTests.swift`](Tests/JerusalemTests/SlideEditorTests.md) | 8 | The pure geometry math (snap, clamp, drag/resize, guides, reorder) plus the rebuilder's promise to never clobber hand-edited slides. |
| [`SlideEditorPart2Tests.swift`](Tests/JerusalemTests/SlideEditorPart2Tests.md) | 8 | Aspect ratio, inspector tabs, zoom math, deep text styling, gradient/color backgrounds, theme copy/apply, and persistence of the new fields. |
| [`SlideLayersTests.swift`](Tests/JerusalemTests/SlideLayersTests.md) | 8 | The Layers panel's reorder math, the renderer drawing strictly in z-order, and the human-readable layer label per element kind. |
| [`PlaylistEditingTests.swift`](Tests/JerusalemTests/PlaylistEditingTests.md) | — | The pure playlist math, a persistence round-trip proving order survives reopen, cascade-delete behavior, and grouped-vs-flat program alignment. |
| [`StressTests.swift`](Tests/JerusalemTests/StressTests.md) | 9 | A service-sized playlist walked end-to-end hundreds of times; snapshots survive their DB being dropped; the prewarmer cache stays bounded. |

---

*This map and the per-file `.md` docs are hand-maintained documentation, not generated on
build. If you add or rename a `.swift` file, add/rename its `.md` and update the matching
row here.*
