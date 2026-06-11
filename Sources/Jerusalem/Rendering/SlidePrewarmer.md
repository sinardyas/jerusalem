# `SlidePrewarmer.swift`

> A bounded LRU cache that pre-renders upcoming slides so advancing the live output is instant instead of waiting on the renderer.

**Location:** `Sources/Jerusalem/Rendering/SlidePrewarmer.swift`
**Role:** cache

## What it does (plain English)

Rendering a slide into a bitmap takes a little time. On Sunday morning you don't want that time to land *at the moment you press the arrow key*. So this class renders the *next* slide ahead of time, at the exact pixel size the output will use, and stashes the finished bitmap in memory. When the view actually needs to show that slide, it finds the bitmap already waiting — a cache hit — and displays it with no render delay.

It's a singleton (`SlidePrewarmer.shared`) — one shared cache for the whole app — and it's an **LRU cache** ("least recently used"): it keeps a small fixed number of bitmaps (6 here) and, when full, evicts the oldest one. That bound is what keeps memory flat; you never accumulate every slide you ever showed.

The cache key combines *which slide* with *what pixel size*, because the same slide rendered for a tiny grid thumbnail and for a 4K projector are different bitmaps. This file deliberately mirrors `VideoPrewarmer` so the same "advance to next slide" hooks can drive both.

## Swift you'll meet in this file

| Swift | JS/TS meaning |
| --- | --- |
| `@MainActor` | Everything here must run on the main/UI thread (enforced by the compiler) |
| `final class SlidePrewarmer` | A reference type (shared, not copied); `final` = cannot be subclassed |
| `static let shared = SlidePrewarmer()` | A module-level singleton instance, like `export const shared = new SlidePrewarmer()` |
| `private struct Key: Hashable` | A value-type compound key usable in a dictionary (`Hashable` ≈ valid `Map` key) |
| `private var cache: [Key: CGImage] = [:]` | `private cache: Map<Key, CGImage> = {}` — a dictionary from key to bitmap |
| `CGImage` | Apple's low-level bitmap image type |
| `func image(for slide:..., pixelSize:) -> CGImage?` | Returns `CGImage | null` |
| `guard let slide else { return nil }` | Early-return null-check (`if (!slide) return null`) |
| `@discardableResult` | "Caller may ignore the return value" without a warning |

## Code walkthrough

The class is a `@MainActor` singleton with three pieces of state — the cache itself, an ordering list for LRU, and the size limit:

```swift
@MainActor
final class SlidePrewarmer {
    static let shared = SlidePrewarmer()

    private struct Key: Hashable {
        let slide: RenderableSlide
        let width: Int
        let height: Int
    }

    private var cache: [Key: CGImage] = [:]
    private var order: [Key] = []
    private let limit = 6
}
```

`Key` bundles the slide snapshot with integer pixel dimensions. This works because `RenderableSlide` is `Hashable` — the cache literally hashes the whole slide's appearance, so any change to the slide produces a different key (and thus a fresh render).

Lookup is a plain dictionary read:

```swift
func image(for slide: RenderableSlide, pixelSize: CGSize) -> CGImage? {
    cache[keyFor(slide, pixelSize: pixelSize)]
}
```

The workhorse is `prewarm`, which is "get-or-render":

```swift
@discardableResult
func prewarm(_ slide: RenderableSlide?, pixelSize: CGSize) -> CGImage? {
    guard let slide else { return nil }
    let key = keyFor(slide, pixelSize: pixelSize)
    if let existing = cache[key] { return existing }
    guard let rendered = SlideRenderer.makeImage(slide, pixelSize: pixelSize) else { return nil }
    store(rendered, for: key)
    return rendered
}
```

Step by step: bail if there's no slide; build the key; return the cached bitmap if present (the fast path); otherwise call the one true renderer, store the result, and return it. Because it returns the image, a caller can both *warm the cache for later* and *use the image now* in one call — which is exactly how `RenderableSlideView` uses it.

LRU eviction lives in `store`:

```swift
private func store(_ image: CGImage, for key: Key) {
    cache[key] = image
    order.append(key)
    while order.count > limit {
        cache.removeValue(forKey: order.removeFirst())
    }
}
```

Every store appends the key to `order`; once `order` exceeds `limit`, it drops the front (oldest) keys until back under the cap. `clear()` empties everything (used by tests), and `cachedCount` exposes the size for assertions.

`keyFor` just rounds the floating-point pixel size to integers so near-identical sizes collapse to the same key:

```swift
Key(slide: slide,
    width: Int(pixelSize.width.rounded()),
    height: Int(pixelSize.height.rounded()))
```

## How it connects

- **Routes through** `SlideRenderer.makeImage` — it never renders by itself, preserving the single-rendering-path invariant. It's a cache *in front of* the one renderer, not a second renderer.
- **Used by** `RenderableSlideView` (`SlideView.swift`): its `.task` calls `SlidePrewarmer.shared.prewarm(...)` to fetch-or-render the slide it's displaying.
- **Driven by** the live program advancing — the same `LiveState.nextProgramSlide` hook that pre-buffers video can call `prewarm` to warm the upcoming slide before it goes live.
- **Keyed on** `RenderableSlide`, which is only possible because that struct is `Hashable`.

## Gotchas / why it matters

- **Main thread only.** `@MainActor` is mandatory because the underlying renderer does AppKit text drawing on the main thread. Don't try to call this from a background task.
- **The bound is the point.** `limit = 6` keeps memory flat. The comment notes it "covers a few thumbnails + live + next + a margin." Raising it trades memory for hit rate; don't make it unbounded.
- **Key includes size.** The same slide at two pixel sizes are two cache entries by design — a thumbnail render never gets mistaken for the full-screen render.
- **Best-effort, not a guarantee.** The header comment is explicit: this is "a structural win, not a timing guarantee." It reduces the chance of a render at switch time; verify real smoothness on hardware.
