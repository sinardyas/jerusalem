# `OutputController.swift`

> Owns the real macOS window that the audience sees, picks the right physical display, and keeps the output alive when displays are unplugged or change resolution.

**Location:** `Sources/Jerusalem/Live/OutputController.swift`
**Role:** AppKit controller (observable store)

## What it does (plain English)

This file is where SwiftUI hands off to AppKit. A church projector is a *second physical display*, and showing a borderless, full-screen window on a specific monitor is something SwiftUI doesn't do well — so `OutputController` reaches down to AppKit's `NSWindow` and `NSScreen` directly.

When the operator clicks "Start Output", it figures out which screen to use (prefer the external projector, fall back to the laptop screen during development), creates a window, fills it with the SwiftUI `OutputView`, and shows it. On an external display the window is borderless and covers the whole screen; on a single-display machine it's a normal resizable "preview" window so it doesn't hijack the developer's screen.

The most important job is **surviving display chaos**. It subscribes to the OS event that fires whenever screens change (`didChangeScreenParameters`). If the resolution changes, it resizes the window. If the active display gets *unplugged*, it fails over to a remaining screen — and if none are left, it stops cleanly. It never crashes. That's the whole point.

This file also contains `ScreenSelection`, a tiny pure rule for *which* screen to use, kept separate so it can be unit-tested without any real hardware.

## Swift you'll meet in this file

- `NSWindow` — a real OS-level window beneath SwiftUI. `// analogy:` a real desktop window object you create/move/resize imperatively (not a React component).
- `NSScreen` — a physical display. `// analogy:` a monitor; `NSScreen.main` is the menu-bar screen, `NSScreen.screens` is all of them.
- `NSHostingController(rootView:)` — wraps a SwiftUI view to live inside an AppKit window. `// analogy:` a React wrapper around a non-React widget — bridges declarative SwiftUI into the imperative window.
- `@MainActor` — everything here runs on the UI thread (`// must run on the main/UI thread`).
- `@Observable final class` — a shared store; views reading `isActive`/`screens` re-render on change → `@observable class X`.
- `NSObject` superclass + `@objc` + `#selector` — Objective-C interop so `NotificationCenter` can call back into Swift → registering a string-named callback.
- `@ObservationIgnored` — a stored property the observation system does *not* track → a field deliberately left out of the reactive store.
- `NotificationCenter.default.addObserver(...)` — subscribing to an OS event → `target.addEventListener("event", handler)`.
- `enum ScreenSelection { static func ... }` — a caseless enum used as a namespace of pure functions → `export const ScreenSelection = { ... }`.
- `extension NSScreen { var displayID ... }` — adds a computed property to an existing type → augmenting a class via its prototype.
- `CGDirectDisplayID` — a stable numeric id for a physical display → a branded `number`.
- `T?`, `??` (nullish), `?.` (optional chaining), `guard ... else { return }` (early return).

## Code walkthrough

`OutputScreen` is a small value type pairing a display's id with its human name (for the screen-picker UI).

```swift
struct OutputScreen: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let name: String
}
```

**TypeScript equivalent**

```ts
interface OutputScreen {        // value type — copied, comparable by value
  readonly id: CGDirectDisplayID;  // stable numeric display id
  readonly name: string;
}
```

`ScreenSelection` is the pure, tested rule:

```swift
enum ScreenSelection {
    static func outputIndex(screenCount: Int, mainIndex: Int) -> Int {
        guard screenCount > 1 else { return 0 }
        return (0..<screenCount).first { $0 != mainIndex } ?? 0
    }
}
```

**TypeScript equivalent**

```ts
// caseless enum used as a namespace of pure functions
const ScreenSelection = {
  outputIndex(screenCount: number, mainIndex: number): number {
    if (screenCount <= 1) return 0;                    // guard … else { return 0 }
    // first index that ISN'T the main screen, else 0 (prefer the projector)
    const idx = [...Array(screenCount).keys()].find(i => i !== mainIndex);
    return idx ?? 0;
  },
};
```

**Swift syntax:**
- `enum ScreenSelection { static func … }` — a *caseless* enum: it has no cases, can't be instantiated, and exists purely as a namespace for static functions. Idiomatic Swift for "a bag of pure helpers" → a plain object of functions / `export const`.
- `(0..<screenCount)` — a half-open `Range` (0 up to, not including, `screenCount`) → `[...Array(n).keys()]`.
- `.first { $0 != mainIndex }` — trailing-closure form of `first(where:)`; returns the first matching element or `nil` → `.find(i => i !== mainIndex)`.
- `?? 0` — nil-coalescing (nullish default), same as TS `?? 0`.

In plain terms: with one screen, use it; with several, use the first one that *isn't* the main (menu-bar) screen — i.e. prefer the projector. No AppKit needed, so it's trivially testable.

The `NSScreen` extension digs the numeric `displayID` out of the screen's device description (with a `?? 0` fallback if it's somehow absent):

```swift
extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
```

**TypeScript equivalent**

```ts
// `extension NSScreen { var displayID }` ⇒ adding a getter to an existing type
// (like patching a prototype / a helper that reads a field off the OS object)
function displayID(screen: NSScreen): CGDirectDisplayID {
  const num = screen.deviceDescription["NSScreenNumber"] as NSNumber | undefined;
  return num?.uint32Value ?? 0;   // optional chaining + nullish fallback
}
```

**Swift syntax:**
- `extension NSScreen { var displayID … }` — adds a computed property to a type you don't own (Apple's `NSScreen`). All `NSScreen`s now have `.displayID`. Like attaching to a prototype.
- `as? NSNumber` — a *conditional cast*: succeeds to `NSNumber?` or yields `nil` (vs. `as!` which would crash on mismatch) → `as X | undefined`.
- `(…)?.uint32Value ?? 0` — optional-chain the cast result, then default to `0`.

`OutputController` itself stores its observable state — `isActive`, `activeScreenID`, `screens` — plus two ignored privates: the raw `window` and a reference to `live` (the `LiveState` it renders). In `init` it refreshes the screen list and subscribes to the OS event:

```swift
@MainActor
@Observable
final class OutputController: NSObject {
    private(set) var isActive = false
    private(set) var activeScreenID: CGDirectDisplayID?
    private(set) var screens: [OutputScreen] = []

    @ObservationIgnored private var window: NSWindow?
    @ObservationIgnored private let live: LiveState

    init(live: LiveState) {
        self.live = live
        super.init()
        refreshScreens()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }
```

**TypeScript equivalent**

```ts
// @observable — views auto-subscribe to isActive / activeScreenID / screens
class OutputController /* extends NSObject for ObjC interop */ {
  #isActive = false;            get isActive() { return this.#isActive; }
  #activeScreenID: CGDirectDisplayID | null = null;
  get activeScreenID() { return this.#activeScreenID; }
  #screens: OutputScreen[] = []; get screens() { return this.#screens; }

  // @ObservationIgnored ⇒ NOT part of the reactive store (raw window + live ref)
  private window: NSWindow | null = null;
  private readonly live: LiveState;  // non-retaining-ish ref to the shared store

  constructor(live: LiveState) {
    this.live = live;
    this.refreshScreens();
    // addObserver(...) ⇒ screen.addEventListener("didChangeScreenParameters", …)
    NotificationCenter.default.addObserver(
      this, "screensChanged",
      NSApplication.didChangeScreenParametersNotification, null);
  }
}
```

**Swift syntax:**
- `final class OutputController: NSObject` — subclasses `NSObject` (required so Objective-C's `NotificationCenter` can target it via `#selector`). `final` = not subclassable.
- `@ObservationIgnored private var window` — opts this field *out* of the `@Observable` change-tracking. The window and `live` reference aren't UI-observable state, so writing them shouldn't re-render views.
- `init(live:)` then `super.init()` — Swift requires you set your own stored properties *before* calling the superclass initializer. `self.live = live` then `super.init()`.
- `#selector(screensChanged)` — a type-safe reference to the method by name, handed to the ObjC runtime → passing the string `"screensChanged"` as the callback name.

`activeOutputPixelSize` computes the *real* pixel resolution of the active display (frame size × `backingScaleFactor` for Retina), falling back to 1920×1080 when there's no window yet. `SlidePrewarmer` uses this to render thumbnails ahead at the correct size.

```swift
var activeOutputPixelSize: CGSize {
    if let id = activeScreenID,
       let screen = NSScreen.screens.first(where: { $0.displayID == id }) {
        let scale = screen.backingScaleFactor
        return CGSize(width: screen.frame.width * scale, height: screen.frame.height * scale)
    }
    return CGSize(width: 1920, height: 1080)
}
```

**TypeScript equivalent**

```ts
get activeOutputPixelSize(): CGSize {
  const id = this.#activeScreenID;
  // `if let id, let screen = …` ⇒ both must be non-null to enter
  if (id != null) {
    const screen = NSScreen.screens.find(s => displayID(s) === id);
    if (screen) {
      const scale = screen.backingScaleFactor;          // Retina factor (e.g. 2)
      return { width: screen.frame.width * scale,
               height: screen.frame.height * scale };
    }
  }
  return { width: 1920, height: 1080 };  // no active window yet
}
```

**Swift syntax:**
- `if let id = …, let screen = …` — chained optional binding: enters the block only if *both* unwrap successfully (a null on either skips it). Like nested `if (id != null) { if (screen) { … } }`.

`preferredScreen()` is where the pure rule meets reality — it finds the main screen's index and asks `ScreenSelection.outputIndex(...)` which screen to return.

```swift
func preferredScreen() -> NSScreen? {
    let all = NSScreen.screens
    guard !all.isEmpty else { return nil }
    let mainIndex = all.firstIndex { $0 == NSScreen.main } ?? 0
    return all[ScreenSelection.outputIndex(screenCount: all.count, mainIndex: mainIndex)]
}
```

**TypeScript equivalent**

```ts
preferredScreen(): NSScreen | null {
  const all = NSScreen.screens;
  if (all.length === 0) return null;                  // guard !isEmpty
  const mainIndex = (() => {
    const i = all.findIndex(s => s === NSScreen.main);
    return i === -1 ? 0 : i;                           // … ?? 0
  })();
  return all[ScreenSelection.outputIndex(all.length, mainIndex)];
}
```

`start(on:)` is the core. It decides `isExternal`, wraps `OutputView` in an `NSHostingController`, reuses the existing window or makes a new one, paints it opaque black, then branches:

```swift
func start(on screen: NSScreen) {
    let isExternal = screen != NSScreen.main
    let hosting = NSHostingController(rootView: OutputView(live: live))

    let win = window ?? makeWindow(external: isExternal, screen: screen)
    win.contentViewController = hosting
    win.isOpaque = true
    win.backgroundColor = .black

    if isExternal {
        win.styleMask = .borderless
        win.level = .floating
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        win.isMovable = false
        win.setFrame(screen.frame, display: true)
    } else {
        win.title = "Audience Output (Preview)"
        win.center()
    }

    win.makeKeyAndOrderFront(nil)
    window = win
    isActive = true
    activeScreenID = screen.displayID
}
```

**TypeScript equivalent**

```ts
start(screen: NSScreen) {
  const isExternal = screen !== NSScreen.main;
  // NSHostingController(rootView:) ⇒ mount the SwiftUI <OutputView> into a real window
  // analogy: ReactDOM.render(<OutputView live={live}/>, someNativeWindowSurface)
  const hosting = new NSHostingController(OutputView({ live: this.live }));

  const win = this.window ?? this.makeWindow(isExternal, screen); // reuse or create
  win.contentViewController = hosting;
  win.isOpaque = true;
  win.backgroundColor = "black";

  if (isExternal) {
    // a true, immovable, all-spaces full-screen surface on the projector
    win.styleMask = "borderless";
    win.level = "floating";
    win.collectionBehavior = ["canJoinAllSpaces", "fullScreenAuxiliary", "stationary"];
    win.isMovable = false;
    win.setFrame(screen.frame, /*display*/ true);
  } else {
    win.title = "Audience Output (Preview)";  // dev: a centered preview window
    win.center();
  }

  win.makeKeyAndOrderFront(null);  // show + focus the window
  this.window = win;
  this.#isActive = true;
  this.#activeScreenID = displayID(screen);
}
```

**Swift syntax:**
- `let win = window ?? makeWindow(...)` — reuse the existing window if present, else build a new one (nil-coalescing as a fallback constructor).
- `win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]` — an *option set* (bit flags) written as an array literal → an array/bitmask of flags.
- `.borderless`, `.floating`, `.black` — leading-dot shorthand for `NSWindow.StyleMask.borderless` etc.; the type is inferred from the assignment target.

The external branch makes a true, immovable, all-spaces full-screen surface; the single-display branch makes a centered, titled preview. `makeWindow(...)` mirrors this split when constructing the `NSWindow` (borderless full frame vs. a 960×540 titled/closable/resizable preview). `stop()` orders the window out, drops the reference, and clears the active state.

The resilience lives in `screensChanged()`:

```swift
@objc private func screensChanged() {
    refreshScreens()
    guard isActive, let id = activeScreenID else { return }

    if let screen = NSScreen.screens.first(where: { $0.displayID == id }) {
        if screen != NSScreen.main { window?.setFrame(screen.frame, display: true) }
    } else if let fallback = preferredScreen() {
        start(on: fallback)   // active display vanished — move to a remaining one
    } else {
        stop()
    }
}
```

**TypeScript equivalent**

```ts
// @objc ⇒ exposed to the ObjC runtime so NotificationCenter can call it
// fires on the "didChangeScreenParameters" event (resolution change / unplug)
private screensChanged() {
  this.refreshScreens();
  const id = this.#activeScreenID;
  if (!(this.#isActive && id != null)) return;   // guard isActive, let id

  const screen = NSScreen.screens.find(s => displayID(s) === id);
  if (screen) {
    // display still exists → just resize to its (possibly new) frame
    if (screen !== NSScreen.main) this.window?.setFrame(screen.frame, true);
  } else {
    const fallback = this.preferredScreen();
    if (fallback) {
      this.start(fallback);   // active display vanished — fail over to a remaining one
    } else {
      this.stop();            // no displays left — stop cleanly (never crash)
    }
  }
}
```

**Swift syntax:**
- `@objc private func screensChanged()` — `@objc` exposes the method to the Objective-C runtime so `NotificationCenter` can invoke it by `#selector`. The event handler.
- `window?.setFrame(...)` — optional chaining: only calls `setFrame` if `window` is non-nil; otherwise a no-op (no crash).

Three outcomes: the display still exists (resize to its new frame), the display vanished but another exists (fail over to it), or no displays remain (stop cleanly). Crucially, none of these paths crashes.

## How it connects

Created once in `JerusalemApp` with the shared `LiveState`, injected via `.environment(...)`. The operator UI calls `toggle()` / `startPreferred()` / `start(screenID:)` / `stop()` and reads `isActive` and `screens` to drive the output controls and screen picker. Inside the window it mounts `OutputView`, which reads `live.content`. `SlidePrewarmer` reads `activeOutputPixelSize`.

## Gotchas / why it matters

- **AppKit owns the output window — by design.** This is one of the project's invariants. The borderless full-screen-on-external behavior is exactly what SwiftUI can't do reliably, so it lives here.
- **Display unplug/replug must never crash.** `screensChanged()` is the safety net: resize, fail over, or stop — but stay alive. This is hardware-dependent and must be verified on a real second display (a headless test can't prove it).
- **`@MainActor`** keeps all window manipulation on the UI thread.
- **`ScreenSelection` is pure on purpose** — the "which screen" decision is the one part that *can* be unit-tested, so it was extracted out of all the AppKit noise.
- The single-display *preview* window exists so developers (and operators rehearsing on a laptop) aren't locked out of their own screen.
