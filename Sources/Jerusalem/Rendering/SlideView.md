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
| `struct RenderableSlideView: View` | A view component ≈ a React function component; shape: `struct Name: View { var body... }` |
| `var body: some View` | The returned UI — `some View` ≈ "returns some JSX element" (an opaque concrete type) |
| `let renderable: RenderableSlide` | An immutable prop passed in at construction (`readonly renderable`) |
| `var aspectRatio: CGFloat = 16.0 / 9.0` | A prop with a default value, like a default React prop |
| `@Environment(\.displayScale) private var displayScale` | Read a value from context (≈ `useContext`); `\.displayScale` is a **key path** selecting which environment value |
| `@State private var image: CGImage?` | Component-local state ≈ `const [image, setImage] = useState<CGImage | null>(null)` |
| `GeometryReader { geo in ... }` | A view that measures itself and hands you `geo.size`; the `{ geo in ... }` is a trailing-closure render prop |
| `if let image { ... } else { ... }` | Conditional rendering with a null-check that binds the unwrapped value |
| `.task(id:) { ... }` | Run async work on appear, re-run when `id` changes ≈ `useEffect(fn, [id])` |
| `ZStack { ... }` | Stack children on the z-axis (on top of each other) |
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

**TypeScript equivalent**

```tsx
// analogy: a React function component with two props and one piece of state.
function RenderableSlideView({
  renderable,
  aspectRatio = 16.0 / 9.0,             // default prop value
}: { renderable: RenderableSlide; aspectRatio?: number }) {
  const displayScale = useContext(DisplayScaleContext); // @Environment(\.displayScale)
  const [image, setImage] = useState<CGImage | null>(null); // @State
  // ...returns JSX (the `body`)
}
```

It takes the snapshot and an aspect ratio as props, reads the screen's `displayScale` from the environment (so a Retina display renders at 2× the points), and keeps the rendered bitmap in `@State`.

**Swift syntax:**
- `struct RenderableSlideView: View` — a view is a **struct** (value type) conforming to `View`; `body` is recomputed like a React render. Stored properties are its props.
- `let renderable` vs `var aspectRatio = ...` — `let` props are required and immutable; a `var` with a default is an optional prop.
- `@Environment(\.displayScale) private var displayScale` — a **property wrapper** that injects a value from the environment (React context). `\.displayScale` is a **key path** naming which value to read.
- `@State private var image: CGImage?` — `@State` makes SwiftUI own this storage and re-render when it changes, exactly like `useState`. `CGImage?` is `CGImage | null`.

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

**TypeScript equivalent**

```tsx
return (
  // analogy: GeometryReader measures and gives you geo.size
  <GeometryReader>
    {(geo) => {
      const pixelSize = {
        width: Math.max(1, geo.size.width * displayScale),
        height: Math.max(1, geo.size.height * displayScale),
      };

      // useEffect keyed on (slide content + integer pixel size):
      useEffect(() => {
        setImage(SlidePrewarmer.shared.prewarm(renderable, pixelSize));
      }, [renderRequestKey(renderable, Math.trunc(pixelSize.width), Math.trunc(pixelSize.height))]);

      return image != null
        ? <Image source={image} scale={displayScale} resizable />
        : <BlackFill />;
    }}
  </GeometryReader>
  // .aspectRatio(16/9, .fit) -> a wrapper that letterboxes to the ratio
);
```

The `.task(id:)` is the key idea. Its `id` is a `RenderRequest` built from the *slide content* and the *integer pixel size*. SwiftUI only re-runs the task when that `id` changes (and `RenderRequest` is `Equatable`, so it compares by value). So resizing by a sub-pixel, or a parent re-render that doesn't change the slide, won't trigger a wasteful re-render.

Inside the task it calls the prewarmer's `prewarm`, which is "get-or-render": a cache hit (e.g. the live output already warmed this slide) returns instantly; a miss renders once and caches it so future mounts are free. The result is assigned to `@State`, which re-renders the view to show the image.

**Swift syntax:**
- `var body: some View` — the computed UI. `some View` is an **opaque return type**: "returns one specific concrete `View` type, you don't need to name it" — like returning `JSX.Element`.
- `GeometryReader { geo in ... }` — a **trailing closure** acting as a render prop; `geo` is the measured proxy (`geo.size`).
- `if let image { ... }` — shorthand optional binding (Swift 5.7+): unwraps `self.image` into a local `image` of the same name; the `if`-branch only runs when non-`nil`.
- `.task(id:) { ... }` — a **view modifier** that runs the trailing closure as async work on appear and re-runs it whenever `id` changes by `==`. The direct analog is `useEffect(fn, [id])`.
- `image = ...` inside the closure mutates `@State`, which triggers a re-render (like calling the `useState` setter).

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

**TypeScript equivalent**

```tsx
function SlideView({ slide, aspectRatio = 16.0 / 9.0 }:
                   { slide: Slide; aspectRatio?: number }) {
  // freeze the mutable model into a value snapshot before rendering
  return <RenderableSlideView renderable={RenderableSlide(slide)} aspectRatio={aspectRatio} />;
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

**TypeScript equivalent**

```tsx
function SlideStageView({ renderable, aspectRatio = 16.0 / 9.0 }:
                        { renderable: RenderableSlide; aspectRatio?: number }) {
  const cue = renderable.backgroundVideo;     // VideoCue | null
  if (cue != null) {
    return (
      // ZStack = stack children on the z-axis, first = bottom
      <ZStack aspectRatio={aspectRatio} contentMode="fit">
        <BlackFill />
        <VideoPlayerView cue={cue} />
        <RenderableSlideView renderable={renderable} />  {/* transparent bg over video */}
      </ZStack>
    );
  }
  return <RenderableSlideView renderable={renderable} aspectRatio={aspectRatio} />;
}
```

When the slide has a motion background, it layers (bottom to top): black, the looping `VideoPlayerView`, then the rendered slide on top — and because the renderer left the slide background transparent for video, the video shows through behind the text. No video? Just the slide. This is used wherever a live slide appears (output and inspector).

**Swift syntax:**
- `if let cue = renderable.backgroundVideo { ... } else { ... }` — optional binding used directly to switch the view tree; the `ZStack` only exists when there's a video cue.
- `ZStack { ... }` — children listed top-down in source are stacked bottom-up on screen (first child is furthest back).

### `RenderRequest` — the change detector

```swift
private struct RenderRequest: Equatable {
    let slide: RenderableSlide
    let width: Int
    let height: Int
}
```

**TypeScript equivalent**

```ts
// A value type whose only job is to be the useEffect dependency key.
interface RenderRequest {
  readonly slide: RenderableSlide;
  readonly width: number;
  readonly height: number;
}
// Two requests are "equal" only if slide AND both ints match (structural ==).
```

A tiny value type whose only job is to be the `.task` identity. Two requests are equal only if the slide *and* the integer dimensions match — that's the precise definition of "a real change worth re-rendering for."

**Swift syntax:**
- `private struct RenderRequest: Equatable` — `Equatable` is auto-synthesized from the stored fields, so SwiftUI can compare two `RenderRequest`s by value to decide whether to re-run the task — exactly what a `useEffect` dependency array does.

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
