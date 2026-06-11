# How Jerusalem Works

A visual tour of the app's moving parts. Three diagrams, each answering one question:

1. **How does typed content become pixels?** (the data + render pipeline)
2. **How does the operator control the audience screen — safely?** (the edit/live firewall)
3. **What happens when the operator presses "next"?** (a step-by-step sequence)

The whole design exists to keep one promise: **never fail on Sunday morning.** Read this
alongside [`CODE-MAP.md`](CODE-MAP.md) (the per-file index) and [`CLAUDE.md`](CLAUDE.md)
(the architecture rules).

> **Reading the arrows:** a **dotted arrow** means *a value-type snapshot is copied* — an
> immutable clone, not a live reference. Those copies are the safety boundary: the renderer
> and the audience screen only ever touch snapshots, never the live database.

---

## 1. From typed content to pixels

You author content in plain language (lyrics, a sermon body, a Bible reference). Parsers and
the `SlideSplitter` turn it into slide-sized chunks, and `ContentRebuilder` writes the actual
`Slide`/`SlideElement` rows. You can also design slides directly on the editor canvas. Then
**one** function — `SlideRenderer.makeImage` — turns any slide into an image, and that single
render path feeds *everything* you see: thumbnails, the inspector preview, and the live screen.

```mermaid
flowchart TD
    IN["✍️ You type<br/>lyrics · sermon body · Bible reference"]

    IN --> PARSE["Parse &amp; fetch<br/>SongLyricsParser ·<br/>BibleReferenceParser → BibleStore"]
    PARSE --> SPLIT["SlideSplitter<br/>chop into slide-sized chunks"]
    SPLIT --> REBUILD["ContentRebuilder.materialize<br/>writes Slide + SlideElement rows<br/>⛔ skips slides you hand-edited"]

    REBUILD --> DB
    EDITOR["🎛 Slide Editor canvas<br/>direct design edits + undo"] --> DB

    DB[("🗄 SwiftData — autosaved on disk<br/>Item → Slide → SlideElement<br/>Playlist · Theme · BibleVerse")]

    DB -.->|"copy to immutable<br/>RenderableSlide"| RENDER
    RENDER["🎨 SlideRenderer.makeImage → CGImage<br/>★ the ONE render path · main thread only"]

    RENDER --> THUMBS["🖼 Grid thumbnails"]
    RENDER --> PREVIEW["🔍 Inspector preview"]
    RENDER --> LIVEOUT["📺 Live audience output"]
```

**Why it's built this way:** because thumbnails, preview, and the audience screen all go
through the *same* renderer, what you see in the grid is exactly what the congregation gets —
there's no second code path that could drift or fail differently on Sunday.

---

## 2. Controlling the live screen — the edit/live firewall

This is the safety-critical part. Editing a slide in the editor or operator window changes the
**database**, but it does **not** change what's on the audience screen. The audience screen
only reflects `LiveState.content`, which is an **immutable snapshot** taken *only when the
operator deliberately acts* (arm / next / go-live). So you can fix a typo mid-service and the
congregation sees nothing change until you choose to push it live.

```mermaid
flowchart LR
    subgraph CONTROL["🖥 Operator Window — your control surface"]
        K["⌨️ Key monitor<br/>←/→/space navigate<br/>B / C / L = Black / Clear / Logo"] --> OPV[OperatorView]
    end

    EDITS["✏️ Edits<br/>editor canvas · inspector"] --> DB
    DB[("🗄 Live SwiftData models")]

    OPV -->|"arm · next · goLive · panic"| GATE
    DB -.->|"snapshot — taken ONLY<br/>on operator action"| GATE

    GATE{{"🧱 Edit / Live firewall<br/>value-type snapshot"}}
    GATE --> LS["📦 LiveState.content<br/>what IS live right now"]

    LS --> OC["OutputController<br/>places NSWindow on the right NSScreen<br/>survives unplug / resolution change"]
    OC --> OV["OutputView<br/>draws slide · video · logo · black"]
    OV --> SCREEN(["👥 Audience screen"])
```

**Two safety behaviors to notice:**

- **Arm vs. go-live.** *Arming* a program loads it without touching the screen; only `next()`
  / `goLive(id:)` actually change output. Loading the next song can't accidentally cut to it.
- **The output window is hardened.** `OutputController` owns a real AppKit `NSWindow`, picks
  the correct display, and watches for displays being unplugged or changing resolution so it
  fails over to a remaining screen instead of crashing. Video falls back to black rather than
  ever taking the output down.

---

## 3. What happens when you press "next"

A concrete walkthrough of advancing one slide during a service. Note the `SlidePrewarmer`: the
*next* slide is usually already rendered and cached, so the screen changes instantly, and the
app immediately pre-warms the slide after that.

```mermaid
sequenceDiagram
    actor Op as Operator
    participant OV as OperatorView
    participant LS as LiveState
    participant PW as SlidePrewarmer
    participant RN as SlideRenderer
    participant OUT as OutputView · audience

    Note over LS,OUT: Program already "armed" (loaded, screen unchanged)
    Op->>OV: press → (next)
    OV->>LS: next()
    LS->>LS: advance index,<br/>build new content snapshot
    LS-->>OUT: content changed → redraw
    OUT->>PW: image for this slide?
    alt already pre-warmed
        PW-->>OUT: cached CGImage (instant)
    else not cached
        PW->>RN: makeImage(snapshot)
        RN-->>PW: CGImage
        PW-->>OUT: CGImage
    end
    OUT-->>Op: audience screen updates
    LS->>PW: pre-warm the slide AFTER this one
```

---

## The whole thing in one breath

- **Author** in plain text → **parsers + `ContentRebuilder`** materialize `Slide` rows in
  **SwiftData** (autosaved, so a crash loses nothing).
- **One renderer** (`SlideRenderer`) draws every slide; thumbnails, preview, and live output
  are guaranteed identical.
- **`LiveState`** holds an **immutable snapshot** of what's on screen — the firewall that lets
  you edit freely without disturbing the congregation until you act.
- **`OutputController` + `OutputView`** own a hardened AppKit window on the projector,
  resilient to unplug/resolution changes, with video that fails to black, never to a crash.

Every arrow above ultimately serves the same goal: **predictable, crash-proof output on
Sunday morning.**
