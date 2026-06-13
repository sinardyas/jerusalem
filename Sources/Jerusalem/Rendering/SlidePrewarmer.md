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
| `@MainActor` | An attribute pinning everything to the main/UI thread (compiler-enforced) — no JS equivalent; think "all methods implicitly run on the UI event loop" |
| `final class SlidePrewarmer` | A reference type (shared, not copied), like any JS `class`; `final` = cannot be subclassed |
| `static let shared = SlidePrewarmer()` | A module-level singleton — `static shared = new SlidePrewarmer()` exposed once |
| `private struct Key: Hashable` | A value-type compound key usable in a dictionary (`Hashable` ≈ a valid `Map` key); shape: `struct Name: Hashable { ... }` |
| `private var cache: [Key: CGImage] = [:]` | `private cache = new Map<Key, CGImage>()`; `[K: V]` is a dictionary, `[:]` is the empty literal |
| `CGImage` | Apple's low-level bitmap image type (no TS equivalent; treat as an opaque bitmap handle) |
| `func image(for slide:..., pixelSize:) -> CGImage?` | Returns `CGImage | null`; the `for`/`pixelSize:` are argument labels, not types |
| `guard let slide else { return nil }` | Early-return null-check that also unwraps — `if (slide == null) return null;` then `slide` is non-null below |
| `@discardableResult` | "Caller may ignore the return value" without a warning (no TS equivalent) |

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

**TypeScript equivalent**

```ts
// @MainActor analogy: imagine every method below implicitly runs on the UI thread.
class SlidePrewarmer {
  static readonly shared = new SlidePrewarmer();

  // value-type compound key — must serialize to a stable Map key (see keyFor)
  // interface Key { slide: RenderableSlide; width: number; height: number }

  private cache = new Map<string, CGImage>();   // key string built from Key
  private order: string[] = [];                 // insertion order, for LRU
  private readonly limit = 6;
}
```

`Key` bundles the slide snapshot with integer pixel dimensions. This works because `RenderableSlide` is `Hashable` — the cache literally hashes the whole slide's appearance, so any change to the slide produces a different key (and thus a fresh render).

**Swift syntax:**
- `@MainActor` — pins the whole class to the main thread; the compiler rejects calls from background tasks. (Required because the renderer it calls does AppKit text drawing, which is main-thread-only.)
- `final class` — a reference type (shared like a JS object), `final` = no subclasses.
- `static let shared = SlidePrewarmer()` — the singleton instance; `let` = immutable binding (`const`).
- `private struct Key: Hashable` — a nested **value-type** key. Because Swift dictionaries hash by value, the compiler-synthesized `Hashable` lets a whole `RenderableSlide` participate in the key (in TS you'd serialize it to a string first — see `keyFor`).
- `[Key: CGImage]` / `[:]` — dictionary type and empty-dictionary literal; the array literal `[]` is the empty list.

Lookup is a plain dictionary read:

```swift
func image(for slide: RenderableSlide, pixelSize: CGSize) -> CGImage? {
    cache[keyFor(slide, pixelSize: pixelSize)]
}
```

**TypeScript equivalent**

```ts
image(slide: RenderableSlide, pixelSize: CGSize): CGImage | null {
  return this.cache.get(this.keyFor(slide, pixelSize)) ?? null;
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

**TypeScript equivalent**

```ts
// @discardableResult: callers may ignore the return without a lint warning.
prewarm(slide: RenderableSlide | null, pixelSize: CGSize): CGImage | null {
  if (slide == null) return null;                 // guard let slide
  const key = this.keyFor(slide, pixelSize);
  const existing = this.cache.get(key);
  if (existing != null) return existing;          // fast path: cache hit
  const rendered = SlideRenderer.makeImage(slide, pixelSize);
  if (rendered == null) return null;              // renderer failed
  this.store(rendered, key);
  return rendered;
}
```

Step by step: bail if there's no slide; build the key; return the cached bitmap if present (the fast path); otherwise call the one true renderer, store the result, and return it. Because it returns the image, a caller can both *warm the cache for later* and *use the image now* in one call — which is exactly how `RenderableSlideView` uses it.

**Swift syntax:**
- `guard let slide else { return nil }` — the **early-exit** form of optional binding: if `slide` is `nil`, run the `else` (which must leave the scope); otherwise `slide` is unwrapped and usable for the rest of the function. Reads as "I require a slide, else give up."
- `if let existing = cache[key] { ... }` — bind-and-test: enter the block only if the dictionary lookup returned non-`nil`, with the value bound to `existing`.

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

**TypeScript equivalent**

```ts
// A Map-based LRU: append on store, drop from the front when over the limit.
private store(image: CGImage, key: string): void {
  this.cache.set(key, image);
  this.order.push(key);
  while (this.order.length > this.limit) {
    const oldest = this.order.shift()!;   // removeFirst()
    this.cache.delete(oldest);
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

**TypeScript equivalent**

```ts
private keyFor(slide: RenderableSlide, pixelSize: CGSize): string {
  const w = Math.round(pixelSize.width);
  const h = Math.round(pixelSize.height);
  // serialize the value-type Key into a stable Map key
  return `${hashSlide(slide)}|${w}x${h}`;
}
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
