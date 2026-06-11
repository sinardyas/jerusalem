# `SlideView.swift`

> The SwiftUI views that display a rendered slide on screen, re-rendering only when the content or pixel size actually changes.

**Location:** `Sources/Jerusalem/Rendering/SlideView.swift`
**Role:** SwiftUI view

## What it does (plain English)

This file is the bridge between the bitmap renderer and the screen. It defines three small SwiftUI views. Think of each `struct ...: View` as a React function component, and `var body: some View` as the JSX it returns.

`RenderableSlideView` is the core one: give it a `RenderableSlide` snapshot, and it figures out its on-screen size, renders the slide to a bitmap (through the prewarmer cache), and shows the image — falling back to black until the bitmap is ready. The clever bit is *when* it re-renders: it uses SwiftUI's `.task(id:)` (≈ React's `useEffect` with a dependency array) keyed on the slide content plus the exact pixel size, so it only re-renders on a real change, not on every layout tick.

`SlideView` is a thin convenience wrapper: hand it a live SwiftData `Slide` and it snapshots it into a `RenderableSlide` and renders that. `SlideStageView` composes the full live picture — if the slide has a motion (video) background, it stacks a looping video behind the transparent-backed slide; otherwise it's just the rendered slide.

## Swift you'll meet in this file

| Swift | JS/TS meaning |
| --- | --- |
| `struct RenderableSlideView: View` | A view component (≈ a React function component) |
| `var body: some View` | The returned UI — `some View` ≈ "returns some JSX element" |
| `let renderable: RenderableSlide` | An immutable prop passed in at construction |
| `var aspectRatio: CGFloat = 16.0 / 9.0` | A prop with a default value |
| `@Environment(\.displayScale) private var displayScale` | Read a value from context (≈ React context) — here the screen's pixel density |
| `@State private var image: CGImage?` | Component-local state (≈ `useState`) holding `CGImage | null` |
| `GeometryReader { geo in ... }` | A view that gives you its measured size (`geo.size`) |
| `if let image { ... } else { ... }` | Conditional rendering with a null-check that binds |
| `.task(id:) { ... }` | Run async work when the view appears, re-run when `id` changes (≈ `useEffect`) |
| `ZStack { ... }` | Stack children on top of each other (z-axis) |
| `private struct RenderRequest: Equatable` | A value type with `==`, used as the `.task` dependency key |

## Code walkthrough

### `RenderableSlideView` — the render-and-display core

```swift
struct RenderableSlideView: View {
    let renderable: RenderableSlide
    var aspectRatio: CGFloat = 16.0 / 9.0

    @Environment(\.displayScale) private var displayScale
    @State private var image: CGImage?
```

It takes the snapshot and an aspect ratio as props, reads the screen's `displayScale` from the environment (so a Retina display renders at 2× the points), and keeps the rendered bitmap in `@State`.

The body measures itself, computes the true pixel size, and shows either the image or black:

```swift
var body: some View {
    GeometryReader { geo in
        let pixelSize = CGSize(width: max(1, geo.size.width * displayScale),
                               height: max(1, geo.size.height * displayScale))
        Group {
            if let image {
                Image(decorative: image, scale: displayScale).resizable()
            } else {
                Color.black
            }
        }
        .task(id: RenderRequest(slide: renderable,
                                width: Int(pixelSize.width),
                                height: Int(pixelSize.height))) {
            image = SlidePrewarmer.shared.prewarm(renderable, pixelSize: pixelSize)
        }
    }
    .aspectRatio(aspectRatio, contentMode: .fit)
}
```

The `.task(id:)` is the key idea. Its `id` is a `RenderRequest` built from the *slide content* and the *integer pixel size*. SwiftUI only re-runs the task when that `id` changes (and `RenderRequest` is `Equatable`, so it compares by value). So resizing by a sub-pixel, or a parent re-render that doesn't change the slide, won't trigger a wasteful re-render.

Inside the task it calls the prewarmer's `prewarm`, which is "get-or-render": a cache hit (e.g. the live output already warmed this slide) returns instantly; a miss renders once and caches it so future mounts are free. The result is assigned to `@State`, which re-renders the view to show the image.

### `SlideView` — snapshot a live model

```swift
struct SlideView: View {
    let slide: Slide
    var aspectRatio: CGFloat = 16.0 / 9.0

    var body: some View {
        RenderableSlideView(renderable: RenderableSlide(slide), aspectRatio: aspectRatio)
    }
}
```

This is where a live SwiftData `Slide` gets frozen into a `RenderableSlide` snapshot (via the `init(_:)` constructor from `RenderableSlide.swift`) before anything renders. From here down, nothing touches the mutable model.

### `SlideStageView` — compose video + slide

```swift
struct SlideStageView: View {
    let renderable: RenderableSlide
    var aspectRatio: CGFloat = 16.0 / 9.0

    var body: some View {
        if let cue = renderable.backgroundVideo {
            ZStack {
                Color.black
                VideoPlayerView(cue: cue)
                RenderableSlideView(renderable: renderable)
            }
            .aspectRatio(aspectRatio, contentMode: .fit)
        } else {
            RenderableSlideView(renderable: renderable, aspectRatio: aspectRatio)
        }
    }
}
```

When the slide has a motion background, it layers (bottom to top): black, the looping `VideoPlayerView`, then the rendered slide on top — and because the renderer left the slide background transparent for video, the video shows through behind the text. No video? Just the slide. This is used wherever a live slide appears (output and inspector).

### `RenderRequest` — the change detector

```swift
private struct RenderRequest: Equatable {
    let slide: RenderableSlide
    let width: Int
    let height: Int
}
```

A tiny value type whose only job is to be the `.task` identity. Two requests are equal only if the slide *and* the integer dimensions match — that's the precise definition of "a real change worth re-rendering for."

## How it connects

- **Snapshots** a SwiftData `Slide` into a `RenderableSlide` (in `SlideView`) — this is where the value-snapshot boundary is crossed.
- **Routes rendering through** `SlidePrewarmer.shared.prewarm`, which in turn is the only caller of `SlideRenderer.makeImage`. So these views are the on-ramp to the single rendering path; they never render directly.
- **Reused everywhere a slide is shown:** the slide grid, the inspector preview, and the live audience output all build on `RenderableSlideView`/`SlideStageView`, which is what makes those surfaces pixel-identical.
- **Composes** `VideoPlayerView` for motion backgrounds.

## Gotchas / why it matters

- **`.task(id:)` is the re-render guard.** The `id` must include everything that affects the pixels (content + size). If you add a field that changes appearance, make sure it flows into the `RenderRequest`/snapshot, or the view won't update.
- **Pixel size, not point size.** It multiplies the measured size by `displayScale` so Retina screens render crisply. Rendering at point size would look soft on Retina.
- **Snapshot before rendering.** `SlideView` deliberately converts the model to a value type first. Don't pass a live `@Model` toward the renderer — it would break edit/live separation.
- **Black is the safe fallback.** Before the image exists (or if rendering returns `nil`), it shows `Color.black` rather than nothing or a crash — consistent with the "never fail on screen" promise.
