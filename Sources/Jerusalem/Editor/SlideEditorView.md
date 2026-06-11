# `SlideEditorView.swift`

> The main editor screen: a three-pane composition (`content rail | canvas | inspector`) that lets the operator author content, design slides on a zoomable WYSIWYG canvas, and tweak per-element properties — all editing the live SwiftData model with undo.

**Location:** `Sources/Jerusalem/Editor/SlideEditorView.swift`
**Role:** SwiftUI view (editor screen composition)

## What it does (plain English)

This is the whole editor laid out. The body is a horizontal split with a status bar underneath: a **left content rail** (where you type lyrics/verses/sermon text, pick a slide from the navigator, and reorder layers), the **canvas/stage** in the middle, and the **inspector** on the right. There's a Show/Edit toggle: *Edit* shows the design canvas; *Show* swaps it for a clean, audience-style preview with no editing chrome.

It owns all the editor-wide state: which slide is selected (`slideID`), which element is selected (`selection`), the toggles (snap/guides/safe-area), the `zoom` level, the inline-text-edit target, and the editor mode. It wires those into its children and reacts to changes (e.g. swapping slides clears the stale element selection).

Two heavier responsibilities live here too: (1) **zoom input** — SwiftUI has no scroll-wheel/pinch handler, so it installs an AppKit `NSEvent` local monitor scoped to *this* window to catch trackpad pinch and ⌘-scroll, funneling them through a Combine subject into the `zoom` state; and (2) **element actions** — Add Text/Image/Shape, Duplicate, Delete, Add Blank Slide — which insert/mutate SwiftData models, theme them, and mark the slide `isManuallyEdited`. It also turns on the SwiftData `UndoManager` so ⌘Z/⌘⇧Z work over every model write.

## Swift you'll meet in this file

- `@Bindable var item: Item` — bind to a SwiftData `@Model`; `@State var slideID`, `@State private var selection`, etc. = `useState`.
- `@Environment(\.dismiss)` — a closure to close the window/sheet; `@Environment(\.modelContext)` — the SwiftData session (insert/delete/undo live here).
- `HSplitView` / `VSplitView` = draggable horizontal/vertical split panes; `ZStack` = layered; `ScrollView([.horizontal, .vertical])` = a 2-axis scroll container.
- `.toolbar { … }` with `@ToolbarContentBuilder` = the window toolbar; `Picker(…).pickerStyle(.segmented)` = a segmented control.
- `.onAppear { }` / `.onDisappear { }` = mount/unmount effects; `.onChange(of: x) { _, new in }` = effect on value change; `.onReceive(publisher) { }` = subscribe to a Combine stream.
- `enum EditorMode: String, CaseIterable, Identifiable` = a string enum that can be listed (`allCases`) and used in `ForEach`.
- `PassthroughSubject<ZoomInput, Never>` (Combine) = an event bus / RxJS-style `Subject` you `.send(...)` into and `.onReceive` out of.
- `NSEvent.addLocalMonitorForEvents(...)`, `NSOpenPanel`, `NSSound.beep()` = AppKit (native macOS) APIs for raw events, file pickers, and the error beep.
- `MainActor.assumeIsolated { … }` = "I know this AppKit callback runs on the main thread, treat it as such."
- `ReferenceWritableKeyPath<SlideElement, Bool>` = a typed pointer to a settable property, like passing `'isBold'` but type-checked; used by `element[keyPath: keyPath].toggle()`.
- `guard let slide else { return }` = early return if optional is nil; `??` = nullish default; `.first(where:)`/`.map(\.order).max()` = array helpers.

## Code walkthrough

### State and the resolved `slide`

The view opens on an **item**, not a slide (a brand-new song has no slides yet). `slideID` is optional; `slide` resolves it, falling back to the first slide:

```swift
private var slide: Slide? {
    if let slideID, let match = item.orderedSlides.first(where: { $0.persistentModelID == slideID }) {
        return match
    }
    return item.orderedSlides.first
}
private var selectedElement: SlideElement? {
    slide?.orderedElements.first { $0.persistentModelID == selection }
}
```

### `body` — the three-pane split + status bar

```swift
VStack(spacing: 0) {
    HSplitView {
        contentRail.frame(minWidth: 204, idealWidth: 255, maxWidth: 374)
        if let slide {
            if editorMode == .edit {
                canvasArea(for: slide).frame(minWidth: 520, minHeight: 360)
                SlideInspectorView(item: item, slide: slide, selectedElement: selectedElement)
                    .frame(minWidth: 238, idealWidth: 272, maxWidth: 340)
            } else {
                showStage(for: slide).frame(minWidth: 520, minHeight: 360)
            }
        } else { placeholder }
    }
    SlideStatusBar(aspectLabel: …, pixelSize: …, snapToGrid: $snapToGrid,
                   showGuides: $showGuides, showSafeArea: $showSafeArea, zoom: zoom)
}
```

`$snapToGrid` etc. pass **two-way bindings** to the status bar so its toggles flip the editor's own state. In Show mode, the inspector and canvas are replaced by `showStage`. If the item has no slide, a `placeholder` (ContentUnavailableView) tells the operator to type content or hit `+`.

The `body` then attaches a stack of effects:

```swift
.toolbar { toolbarContent }
.navigationTitle(item.title.isEmpty ? "Edit Slide" : item.title)
.background(keyboardShortcuts)            // invisible buttons that bind ⌘Z/⌘D/⌘B…
.background(WindowAccessor { editorWindowRef.window = $0 })   // grab the NSWindow
.onReceive(zoomInput) { applyZoom($0) }
.onAppear {
    if modelContext.undoManager == nil { modelContext.undoManager = UndoManager() }
    selection = nil
    installZoomMonitor()
}
.onDisappear(perform: removeZoomMonitor)
.onChange(of: slideID) { _, _ in selection = nil; inlineEditTarget = nil }
.onChange(of: editorMode) { _, _ in inlineEditTarget = nil }
```

Note `.onAppear` **opts into undo** by assigning an `UndoManager` to the model context (SwiftData doesn't track undo unless you ask), and clears stale selection. The `onChange` handlers prevent a handle/inline-editor from the *previous* slide or mode lingering.

### Zoom: bridging AppKit events into state

SwiftUI can't see scroll-wheel/pinch, so a local AppKit monitor does it, scoped to this window:

```swift
zoomMonitor = NSEvent.addLocalMonitorForEvents(matching: [.magnify, .scrollWheel]) { event in
    MainActor.assumeIsolated {
        guard event.window === windowRef.window else { return event }   // only THIS window
        switch event.type {
        case .magnify:
            input.send(.magnify(event.magnification)); return nil       // consume
        case .scrollWheel where event.modifierFlags.contains(.command):
            let scale: CGFloat = event.hasPreciseScrollingDeltas ? 0.004 : 0.04
            input.send(.scroll(event.scrollingDeltaY * scale)); return nil
        default: return event                                           // pass through (plain scroll pans)
        }
    }
}
```

Events go into the `zoomInput` Combine subject; `.onReceive(zoomInput)` calls `applyZoom`, which delegates the actual clamping/math to `CanvasZoomMath` (see `ZoomBar.md`). Returning `nil` consumes the event; returning `event` lets it pass (so non-⌘ scroll still pans the canvas).

### `canvasArea` — the desk, the scrollable stage, the zoom bar

```swift
private func canvasArea(for slide: Slide) -> some View {
    let aspect = item.aspectRatioValue
    let canvasHeight = 760 / aspect
    return ZStack {
        EditorDeskBackdrop().ignoresSafeArea()
        ScrollView([.horizontal, .vertical]) {
            ZStack {
                SlideCanvasView(slide: slide, selection: $selection,
                                snapToGrid: snapToGrid, showSafeArea: showSafeArea,
                                showGuides: showGuides, aspectRatio: aspect,
                                toastCenter: toastCenter,
                                onInlineEditRequest: { element in
                                    inlineEditCanvasSize = CGSize(width: 760 * zoom, height: canvasHeight * zoom)
                                    inlineEditTarget = element },
                                onDuplicate: duplicate, onDelete: delete)
                if let element = inlineEditTarget, /* still exists */ {
                    inlineEditOverlay(for: element, slide: slide,
                                      canvasSize: CGSize(width: 760 * zoom, height: canvasHeight * zoom))
                }
            }
            .frame(width: 760 * zoom, height: canvasHeight * zoom)
            .padding(.horizontal, 760 * zoom * SlideGeometry.pasteboardMargin)
            .padding(.vertical, canvasHeight * zoom * SlideGeometry.pasteboardMargin)
        }
        .defaultScrollAnchor(.center)
        EditorToast(center: toastCenter)
    }
    .overlay(alignment: .bottomLeading) { ZoomBar(zoom: $zoom).padding(14) }
}
```

The canvas is sized `760 × canvasHeight` **× `zoom`**, inside a 2-axis scroll view, with a "pasteboard" margin (using `SlideGeometry.pasteboardMargin`) so elements dragged off the slide stay reachable on the desk. The inline text editor floats over it when active, sized to the *current* pixel canvas. `ZoomBar` sits bottom-left, bound to `$zoom`.

### Inline text editing — WYSIWYG overlay

When the canvas double-clicks a text element, `inlineEditOverlay` floats a native editor over its frame, **matching its rendered look** (font, size scaled to canvas, color, alignment):

```swift
let scaledSize = element.fontSize * canvasSize.height / SlideRenderer.referenceHeight
let baseFont = Font.custom(element.fontName, size: scaledSize)
    .weight(element.isBold ? .bold : .regular)
let font = element.isItalic ? baseFont.italic() : baseFont
return InlineTextEditOverlay(initialText: element.text ?? "", frame: rect, font: font, …,
    onCommit: { newText in
        if newText != (element.text ?? "") { element.text = newText; slide.isManuallyEdited = true }
        inlineEditTarget = nil
    },
    onCancel: { inlineEditTarget = nil })
```

Note `fontSize` is points at the 1920×1080 reference, so it's scaled by `canvasSize.height / SlideRenderer.referenceHeight` to match what's on screen. Committing writes `element.text` and marks the slide edited.

### Keyboard shortcuts and the toolbar

`keyboardShortcuts` is a clever trick: a `ZStack` of **invisible, zero-size buttons**, each bound to a shortcut, used purely to register ⌘Z / ⌘⇧Z (undo/redo), ⌘D (duplicate), and ⌘B/I/U (toggle bold/italic/underline on the selected text). Disabled buttons don't fire, which gates the shortcuts contextually. Delete is *deliberately not* a global shortcut (⌘⌫ collides with text-field editing) — it lives on the canvas right-click menu instead.

`toolbarContent` builds the top bar: the Show/Edit picker, the object tools (Text/Image/Shape/Background) + Undo/Redo (all disabled in Show mode), the aspect-ratio picker (16:9 / 4:3, bound through a custom get/set `Binding`), and **Done** (⌘↩, dismisses).

### Element & slide actions (the model mutations)

These are the methods that actually change the document. They follow a consistent recipe — create, theme/place, `modelContext.insert`, append to the relationship, mark edited, select:

```swift
private func addText() {
    guard let slide else { return }
    let element = SlideElement(kind: .text, order: nextOrder(in: slide), text: "Type here…")
    (item.theme ?? Theme.makeDefault()).apply(to: element)
    element.x = 0.10; element.y = 0.40; element.width = 0.80; element.height = 0.20   // normalized!
    modelContext.insert(element)
    slide.elements.append(element)
    slide.isManuallyEdited = true
    selection = element.persistentModelID
}
```

`addShape`/`addImage` are siblings (`addImage` uses an `NSOpenPanel` + `MediaStorage.importFile` to copy the picked file into app storage). `duplicate` deep-copies every styling field and offsets the copy by `0.04` (capped at `0.9`). `delete` removes from the relationship, calls `modelContext.delete`, and clears selection/inline-edit if they pointed at it. `addBlankSlide` appends a themed `Slide` at the next order. Every one ends by flipping `isManuallyEdited`.

## How it connects

- **Down to children:** hands `slide` + `$selection` + toggles + callbacks to `SlideCanvasView`; `item`/`slide`/`selectedElement` to `SlideInspectorView`; `item` + `$slideID` + `onAddSlide` to `SlideNavigatorView`; `$zoom` to `ZoomBar`. The content rail (`VSplitView`) hosts the per-kind content editor, the navigator, and the Layers panel.
- **Up from children:** the navigator sets `slideID`; the canvas sets `selection`, fires `onInlineEditRequest`/`onDuplicate`/`onDelete`, and shows snap toasts via `toastCenter`; the status bar flips the toggles.
- **`SlideGeometry`:** used here only for `pasteboardMargin` (the desk overflow padding); the gesture math itself lives in the canvas.
- **Persistence/undo:** all inserts/deletes/edits go through `modelContext`, whose `UndoManager` (enabled in `.onAppear`) backs ⌘Z. Closing the window (see `SlideEditorWindowRoot`) re-arms `LiveState`.

## Gotchas / why it matters

- **Opens on an item, not a slide.** A new song has zero slides; the placeholder + content rail drive `ContentRebuilder` to materialize them. Don't assume `slide` is non-nil.
- **Undo is opt-in.** The `UndoManager` assignment in `.onAppear` is what makes ⌘Z work — remove it and undo silently dies.
- **Zoom needs the AppKit monitor.** SwiftUI alone can't do pinch/⌘-scroll. The monitor is window-scoped (`event.window === windowRef.window`) so it never zooms a different editor window, and removed in `.onDisappear` to avoid leaks.
- **Everything placed in 0…1.** New elements use normalized frames (`0.10, 0.40, 0.80, 0.20`), and `fontSize` is points at the 1920×1080 reference (scaled for the inline editor).
- **`isManuallyEdited` everywhere.** Every action sets it so `ContentRebuilder` won't overwrite the operator's design.
- **Live model editing is safe.** Changes show instantly in thumbnails/preview, but the audience output is shielded by `LiveState`'s snapshot until the operator acts.
