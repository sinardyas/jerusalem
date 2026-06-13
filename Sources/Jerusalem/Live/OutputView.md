# `OutputView.swift`

> The SwiftUI view inside the audience window — it reads `LiveState.content` and draws the right thing (slide, video, logo, or black) full-bleed with an optional fade.

**Location:** `Sources/Jerusalem/Live/OutputView.swift`
**Role:** SwiftUI view

## What it does (plain English)

This is the actual picture the congregation sees. It's a thin, declarative SwiftUI view: it looks at `live.content` (the resolved snapshot from `LiveState`) and switches to the matching sub-view. Everything sits on a black background and ignores safe-area insets, so it truly fills the projector.

Because `LiveState` already did all the deciding (panic, clear, which slide, etc.), `OutputView` has no logic of its own beyond "given this `Content` case, show that view." When `content` changes, SwiftUI optionally cross-fades between the old and new view based on the operator's chosen transition style.

It also defines `LogoView`, the simple placeholder shown when the operator hits the Logo panic key.

## Swift you'll meet in this file

- `struct ... : View` — a SwiftUI view is a value type with a `body` → a function component returning JSX. Shape: `struct OutputView: View { var body: some View { … } }`.
- `var body: some View` — the rendered tree; `some View` is an *opaque return type* ("some concrete View, hidden") → `(): ReactNode` where the exact type is inferred.
- `ZStack` — stacks children back-to-front (z-axis) → absolutely-positioned layers / `position: absolute` stacking.
- `@ViewBuilder` — lets a computed property return different views from a `switch` → a function returning different JSX branches.
- `switch live.content` — exhaustive matching over the `Content` union; `case .slide(let renderable)` binds the associated value → `switch (content.kind) { case "slide": … }`.
- `.id(...)`, `.transition(...)`, `.animation(...)`, `.ignoresSafeArea()` — view modifiers (chained config) → props / HOC wrappers.
- Closures `{ ... }` = arrow functions (the `onEnded` callback).
- `==` comparisons on enums drive the conditional animation.

## Code walkthrough

The body stacks black behind the resolved content and attaches a fade:

```swift
var body: some View {
    ZStack {
        Color.black
        content
            .id(live.content)
            .transition(.opacity)
    }
    .ignoresSafeArea()
    .animation(live.transition == .fade ? .easeInOut(duration: 0.3) : nil,
               value: live.content)
}
```

**TypeScript equivalent**

```tsx
// pseudo-JSX: `var body: some View` ≈ a function component's return
function OutputView({ live }: { live: LiveState }) {
  return (
    // ZStack = back-to-front layers; black sits behind the content
    <ZStack
      ignoresSafeArea               // .ignoresSafeArea() — fill to the edges
      animation={live.transition === "fade"
        ? { easeInOut: 0.3 } : null} // null ⇒ instant cut, no animation
      animationKey={live.content}>   {/* value: live.content */}
      <ColorBlack />
      <Content
        key={live.content}           {/* .id(live.content) — see note below */}
        transition="opacity" />      {/* .transition(.opacity) — cross-fade */}
    </ZStack>
  );
}
```

**Swift syntax:**
- `var body: some View` — every SwiftUI view has a `body` computed property returning `some View` (an opaque type: the compiler knows the concrete type, you don't have to name it). Like a component whose return type is "some ReactNode, inferred."
- `ZStack { … }` — a container whose trailing closure *is* its children; views listed inside stack on the z-axis. There are no commas — each line is a child view.
- `.modifier(...)` chains — `.id`, `.transition`, `.ignoresSafeArea`, `.animation` each return a new wrapped view (like chaining HOCs / spreading props). They read top-to-bottom but wrap outermost-last.
- `.animation(cond ? .easeInOut(...) : nil, value:)` — animates changes to `value:` *only* when the first arg is non-nil; passing `nil` means "no animation" (the hard cut).

The `.id(live.content)` is doing something subtle: by tying the view's identity to the *content value*, SwiftUI treats a content change as "remove the old view, insert a new one," which is what makes the opacity transition cross-fade. The `.animation(...)` modifier only animates when the operator picked `.fade`; for `.cut` it passes `nil`, giving an instant hard cut. Both are keyed on `value: live.content` so the animation fires precisely when content changes. (Same idea as a React `key` prop: change the `key` and React unmounts the old node and mounts a fresh one.)

`content` is the `@ViewBuilder` switch that maps each case to a view:

```swift
@ViewBuilder private var content: some View {
    switch live.content {
    case .empty, .black:
        Color.clear
    case .logo:
        LogoView()
    case .slide(let renderable):
        SlideStageView(renderable: renderable)
    case .video(let cue):
        VideoPlayerView(cue: cue, onEnded: {
            if cue.endBehavior == .advance { live.next() }
        })
    }
}
```

**TypeScript equivalent**

```tsx
// @ViewBuilder lets this getter return different JSX per branch
function Content({ live }: { live: LiveState }) {
  switch (live.content.kind) {
    case "empty":
    case "black":
      return <ColorClear />;          // black ZStack backdrop already shows through
    case "logo":
      return <LogoView />;
    case "slide":
      return <SlideStageView renderable={live.content.slide} />;
    case "video":
      // onEnded callback ⇒ auto-advance when the clip is set to "advance"
      return <VideoPlayerView
        cue={live.content.cue}
        onEnded={() => {
          if (live.content.cue.endBehavior === "advance") live.next();
        }} />;
  }
}
```

**Swift syntax:**
- `@ViewBuilder private var content: some View` — `@ViewBuilder` is a result builder that lets a `switch` (whose branches return *different* view types) work as one `some View`. Without it, a property/closure can return only one concrete type. Think of it as the thing that makes "return different JSX from each `case`" legal.
- `case .empty, .black:` — one branch matching multiple cases (comma-separated) → stacked `case "empty": case "black":` with shared body.
- `case .slide(let renderable):` — matches the `.slide` case and binds its associated value to `renderable` → `case "slide": const renderable = content.slide`.
- `VideoPlayerView(cue: cue, onEnded: { … })` — passing a trailing closure as the `onEnded` prop → an arrow function prop.

A few things to notice:

- `.empty` and `.black` both render `Color.clear` — the black `ZStack` background already provides the blackness, so "empty" and "black" look identical here. (`LiveState` distinguishes them logically; visually they're both just the black backdrop.)
- `.slide` hands the value snapshot to `SlideStageView` (which renders it through the shared `SlideRenderer`).
- `.video` mounts `VideoPlayerView` and wires its `onEnded` callback so that a clip set to "advance" tells `LiveState` to move to the next slide automatically.

`LogoView` is a placeholder holding-slide — just the word "Jerusalem" in light serif, centered:

```swift
struct LogoView: View {
    var body: some View {
        Text("Jerusalem")
            .font(.system(size: 64, weight: .light, design: .serif))
            .foregroundStyle(.white.opacity(0.85))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

**TypeScript equivalent**

```tsx
function LogoView() {
  return (
    <Text
      // chained modifiers ≈ a style object
      style={{
        font: { size: 64, weight: "light", design: "serif" },
        color: rgba(255, 255, 255, 0.85),   // .white.opacity(0.85)
        width: "100%", height: "100%",       // .frame(maxWidth/Height: .infinity)
      }}>
      Jerusalem
    </Text>
  );
}
```

**Swift syntax:**
- `.frame(maxWidth: .infinity, maxHeight: .infinity)` — tells the view to expand to fill all available space → `width: 100%; height: 100%`.
- `.white.opacity(0.85)` — a color with 85% alpha → `rgba(255,255,255,0.85)`.

The comment notes a user-configurable logo image is a later phase.

## How it connects

`OutputView` is mounted inside the `NSWindow` by `OutputController` (via `NSHostingController(rootView: OutputView(live: live))`). It reads `live.content` and `live.transition` from the shared `LiveState`. Slides flow to `SlideStageView` → the shared `SlideRenderer`; video flows to `VideoPlayerView`. The `onEnded` callback flows *back* into `LiveState.next()`, closing the loop for auto-advancing clips.

## Gotchas / why it matters

- **It holds no logic and no state of its own.** All decisions were made in `LiveState`; this view just renders the resolved `content`. That separation is what keeps the output predictable.
- **Value snapshots only.** It receives `RenderableSlide` / `VideoCue` structs, never live models — so it physically can't render half-edited data.
- **Fade vs. cut** is operator-controlled via `live.transition`; the `.id(live.content)` trick is what enables the cross-fade.
- **Auto-advance on video end** is wired here through the `onEnded` closure — a clip with `endBehavior == .advance` drives the program forward without operator action.
