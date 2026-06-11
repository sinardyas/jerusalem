# `RenderableSlide.swift`

> Immutable value-type snapshots of a slide and its elements — the only data shape the renderer and live output are allowed to touch.

**Location:** `Sources/Jerusalem/Rendering/RenderableSlide.swift`
**Role:** value-type model

## What it does (plain English)

This file defines two plain data structures — `RenderableSlide` and `RenderableElement` — that describe *exactly what a slide should look like*: its background, and a list of elements (text boxes, images, shapes) with their position, font, color, and effects. There's no behavior here beyond a couple of constructors; these are the "frozen photographs" of a slide.

The crucial idea is that these are **value types** (`struct`), so they're copied whenever you pass them around. In JS terms, imagine if every object were deep-frozen and cloned on assignment. That copy-on-pass behavior is *why* the app can safely separate editing from the live audience screen: the renderer holds a snapshot, and editing the underlying database model later can't reach back and mutate what's already on screen.

The two `init(_:)` constructors at the bottom are the bridge from the live, mutable SwiftData models (`Slide` and `SlideElement`) into these frozen snapshots. You hand them a database model, and they read out every field into a copy. After that point, the database can change all it wants — the snapshot is untouched.

## Swift you'll meet in this file

| Swift | JS/TS meaning |
| --- | --- |
| `struct RenderableSlide { ... }` | A value type — copied on every pass/assignment (not shared by reference) |
| `var backgroundColorHex: String` | A mutable field of type `string`. (`var` = `let` in JS; `let` would be `const`) |
| `: Equatable, Hashable, Sendable` | Protocols (≈ TS interfaces): `Equatable` gives `==`, `Hashable` lets it be a `Map`/`Set` key, `Sendable` means "safe to move across threads" |
| `var elements: [RenderableElement]` | `RenderableElement[]` — an array |
| `VideoCue? = nil` | `VideoCue | null`, defaulting to `null` |
| `URL?` | `URL | null` |
| `extension RenderableSlide { ... }` | Add methods/initializers to an existing type, like reopening a class to bolt on more |
| `init(_ slide: Slide)` | A constructor; the `_` means the argument is positional (no label at the call site) |
| `if slide.backgroundKind == .video, let filename = ...` | Combined null-check + bind; both conditions must pass |
| `.map(RenderableElement.init)` | `array.map(x => new RenderableElement(x))` — passing the constructor as the callback |

## Code walkthrough

`RenderableSlide` holds the background and the element list:

```swift
struct RenderableSlide: Equatable, Hashable, Sendable {
    var backgroundKind: SlideBackgroundKind = .color
    var backgroundColorHex: String
    var elements: [RenderableElement]
    var backgroundVideo: VideoCue? = nil
    var backgroundImageURL: URL? = nil
    var gradientHex2: String? = nil
    var gradientAngle: Double = 135
}
```

The defaults (`= .color`, `= nil`, `= 135`) mean those fields are optional at construction — a slide is a solid color unless told otherwise. `backgroundVideo` and `backgroundImageURL` are only "live" when `backgroundKind` is `.video` / `.image` respectively (the comments spell this out). For a video background the renderer deliberately leaves the slide transparent so the looping video shows through behind the text.

`RenderableElement` is one item on the slide. Note the **normalized coordinates**:

```swift
struct RenderableElement: Equatable, Hashable, Sendable {
    var kind: SlideElementKind
    var text: String?
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    ...
}
```

`x`, `y`, `width`, `height` are all `0...1` fractions with a top-left origin (e.g. `x: 0.5` is halfway across), so the same element lays out correctly whether the audience screen is 1280×720 or 4K. `fontSize` is "points at a 1920×1080 reference" — the renderer scales it by the real output height. Everything else is styling: font, color hex, alignment, bold/italic/underline, shadow, stroke, and shape fields. Many have defaults (`var strokeWidth: Double = 3.0`, etc.) so older snapshots and the auto-synthesized `Equatable`/`Hashable` keep working when new fields are added.

The two extensions convert from database models. For a slide:

```swift
init(_ slide: Slide) {
    var motionBackground: VideoCue?
    if slide.backgroundKind == .video,
       let filename = slide.backgroundVideoFilename,
       MediaImport.kind(forExtension: (filename as NSString).pathExtension) == .video {
        motionBackground = VideoCue(url: MediaStorage.url(forFilename: filename),
                                    loops: true, muted: true, endBehavior: .hold)
    }
    ...
    self.init(
        backgroundKind: slide.backgroundKind,
        backgroundColorHex: slide.backgroundColorHex,
        elements: slide.orderedElements.map(RenderableElement.init),
        ...)
}
```

It only wires up a motion background if the kind is `.video` *and* the stored filename actually is a video file — a defensive check so a stale/mismatched filename can't produce a broken cue. The line `elements: slide.orderedElements.map(RenderableElement.init)` snapshots every element by running each through the `RenderableElement(_:)` constructor, which simply copies all fields across one-to-one.

A doc comment flags an important rule: this snapshotting *"must be called on the actor that owns the model (the main actor for the app's main context)"* — you read a SwiftData model on the main thread.

## How it connects

These structs are the contract at the heart of the renderer:

- **Produced from** SwiftData `Slide` / `SlideElement` via the `init(_:)` constructors (typically inside `SlideView`, which wraps a `Slide`).
- **Consumed by** `SlideRenderer.makeImage(_:pixelSize:)`, which only ever accepts a `RenderableSlide` — never a live model.
- **Cached by** `SlidePrewarmer`, which uses `RenderableSlide` as part of its dictionary key (possible only because it's `Hashable`).
- **Diffed by** `RenderableSlideView` to decide whether to re-render (possible only because it's `Equatable`).

This is the "value snapshots" invariant in code form: nothing downstream of these structs can see a mutable model, so editing never disturbs the audience screen.

## Gotchas / why it matters

- **Value, not reference.** Because these are `struct`s, passing one *copies* it. That is the entire safety mechanism — there's no shared mutable state to accidentally change mid-service. Don't try to turn these into `class`es for "efficiency"; you'd break edit/live separation.
- **Normalized coordinates are a hard rule.** Keep `x/y/width/height` in `0...1` and `fontSize` at the 1920×1080 reference. Pixel values here would break on every other resolution.
- **Snapshot on the main actor.** The `init(_:)` constructors read SwiftData models, so call them on the main thread/actor that owns the context.
- **Defaults protect compatibility.** New fields get default values so existing call sites, and the compiler's free `Equatable`/`Hashable`, keep compiling. Follow that pattern when adding fields.
