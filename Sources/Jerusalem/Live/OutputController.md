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

- `NSWindow` — a real OS-level window (the AppKit layer beneath SwiftUI).
- `NSScreen` — a physical display. `NSScreen.main` is the menu-bar screen; `NSScreen.screens` is all of them.
- `NSHostingController(rootView:)` — wraps a SwiftUI view so it can live inside an AppKit window (the bridge from React-land into the old widget).
- `@MainActor` — everything here runs on the UI thread (windows are UI).
- `@Observable final class` — a shared store; views that read `isActive`/`screens` re-render on change.
- `NSObject` superclass + `@objc` + `#selector` — needed so `NotificationCenter` can call back into Swift (Objective-C interop machinery).
- `@ObservationIgnored` — marks a stored property the observation system should *not* track (the raw `window` and the `live` reference aren't UI-observable state).
- `NotificationCenter.default.addObserver(...)` — subscribing to an OS event, like `window.addEventListener`.
- `enum ScreenSelection { static func ... }` — a caseless enum used as a namespace of pure functions (`export const ScreenSelection = { ... }`).
- `extension NSScreen { var displayID ... }` — adds a computed property to an existing type (like augmenting a class via prototype).
- `CGDirectDisplayID` — a stable numeric id for a physical display.
- `T?`, `??` (nullish), `?.` (optional chaining), `guard ... else { return }` (early return).

## Code walkthrough

`OutputScreen` is a small value type pairing a display's id with its human name (for the screen-picker UI).

`ScreenSelection` is the pure, tested rule:

```swift
enum ScreenSelection {
    static func outputIndex(screenCount: Int, mainIndex: Int) -> Int {
        guard screenCount > 1 else { return 0 }
        return (0..<screenCount).first { $0 != mainIndex } ?? 0
    }
}
```

In plain terms: with one screen, use it; with several, use the first one that *isn't* the main (menu-bar) screen — i.e. prefer the projector. No AppKit needed, so it's trivially testable.

The `NSScreen` extension digs the numeric `displayID` out of the screen's device description (with a `?? 0` fallback if it's somehow absent).

`OutputController` itself stores its observable state — `isActive`, `activeScreenID`, `screens` — plus two ignored privates: the raw `window` and a reference to `live` (the `LiveState` it renders). In `init` it refreshes the screen list and subscribes to the OS event:

```swift
NotificationCenter.default.addObserver(
    self, selector: #selector(screensChanged),
    name: NSApplication.didChangeScreenParametersNotification, object: nil)
```

`activeOutputPixelSize` computes the *real* pixel resolution of the active display (frame size × `backingScaleFactor` for Retina), falling back to 1920×1080 when there's no window yet. `SlidePrewarmer` uses this to render thumbnails ahead at the correct size.

`preferredScreen()` is where the pure rule meets reality — it finds the main screen's index and asks `ScreenSelection.outputIndex(...)` which screen to return.

`start(on:)` is the core. It decides `isExternal`, wraps `OutputView` in an `NSHostingController`, reuses the existing window or makes a new one, paints it opaque black, then branches:

```swift
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
```

The external branch makes a true, immovable, all-spaces full-screen surface; the single-display branch makes a centered, titled preview. `makeWindow(...)` mirrors this split when constructing the `NSWindow` (borderless full frame vs. a 960×540 titled/closable/resizable preview).

`stop()` orders the window out, drops the reference, and clears the active state.

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

Three outcomes: the display still exists (resize to its new frame), the display vanished but another exists (fail over to it), or no displays remain (stop cleanly). Crucially, none of these paths crashes.

## How it connects

Created once in `JerusalemApp` with the shared `LiveState`, injected via `.environment(...)`. The operator UI calls `toggle()` / `startPreferred()` / `start(screenID:)` / `stop()` and reads `isActive` and `screens` to drive the output controls and screen picker. Inside the window it mounts `OutputView`, which reads `live.content`. `SlidePrewarmer` reads `activeOutputPixelSize`.

## Gotchas / why it matters

- **AppKit owns the output window — by design.** This is one of the project's invariants. The borderless full-screen-on-external behavior is exactly what SwiftUI can't do reliably, so it lives here.
- **Display unplug/replug must never crash.** `screensChanged()` is the safety net: resize, fail over, or stop — but stay alive. This is hardware-dependent and must be verified on a real second display (a headless test can't prove it).
- **`@MainActor`** keeps all window manipulation on the UI thread.
- **`ScreenSelection` is pure on purpose** — the "which screen" decision is the one part that *can* be unit-tested, so it was extracted out of all the AppKit noise.
- The single-display *preview* window exists so developers (and operators rehearsing on a laptop) aren't locked out of their own screen.
