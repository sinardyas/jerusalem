# `SlideEditorView.swift`

> The main editor screen: a three-pane composition (`content rail | canvas | inspector`) that lets the operator author content, design slides on a zoomable WYSIWYG canvas, and tweak per-element properties — all editing the live SwiftData model with undo.

**Location:** `Sources/Jerusalem/Editor/SlideEditorView.swift`
**Role:** SwiftUI view (editor screen composition)

## What it does (plain English)

This is the whole editor laid out. The body is a horizontal split with a status bar underneath: a **left content rail** (where you type lyrics/verses/sermon text, pick a slide from the navigator, and reorder layers), the **canvas/stage** in the middle, and the **inspector** on the right. There's a Show/Edit toggle: *Edit* shows the design canvas; *Show* swaps it for a clean, audience-style preview with no editing chrome.

It owns all the editor-wide state: which slide is selected (`slideID`), which element is selected (`selection`), the toggles (snap/guides/safe-area), the `zoom` level, the inline-text-edit target, and the editor mode. It wires those into its children and reacts to changes (e.g. swapping slides clears the stale element selection).

Two heavier responsibilities live here too: (1) **zoom input** — SwiftUI has no scroll-wheel/pinch handler, so it installs an AppKit `NSEvent` local monitor scoped to *this* window to catch trackpad pinch and ⌘-scroll, funneling them through a Combine subject into the `zoom` state; and (2) **element actions** — Add Text/Image/Shape, Duplicate, Delete, Add Blank Slide — which insert/mutate SwiftData models, theme them, and mark the slide `isManuallyEdited`. It also turns on the SwiftData `UndoManager` so ⌘Z/⌘⇧Z work over every model write.

## Swift you'll meet in this file

- `struct SlideEditorView: View { var body: some View }` — SwiftUI view ≈ React component; `some View` = opaque return type.
- `@Bindable var item: Item` — bind to a SwiftData `@Model`; `@State var slideID`, `@State private var selection`, etc. = `useState`.
- `@Environment(\.dismiss)` — pull a "close the window/sheet" closure out of context; `@Environment(\.modelContext)` — the SwiftData session (insert/delete/undo live here). `\.dismiss` is a key path into the environment.
- `HSplitView` / `VSplitView` = draggable horizontal/vertical split panes; `ZStack` = layered; `ScrollView([.horizontal, .vertical])` = a 2-axis scroll container.
- `.toolbar { … }` with `@ToolbarContentBuilder` = the window toolbar; `Picker(…).pickerStyle(.segmented)` = a segmented control.
- `.onAppear { }` / `.onDisappear { }` = mount/unmount effects; `.onChange(of: x) { _, new in }` = effect on value change; `.onReceive(publisher) { }` = subscribe to a Combine stream.
- `enum EditorMode: String, CaseIterable, Identifiable` = a string enum that can be listed (`allCases`) and used in `ForEach`.
- `PassthroughSubject<ZoomInput, Never>` (Combine) = an event bus / RxJS-style `Subject` you `.send(...)` into and `.onReceive` out of.
- `enum ZoomInput { case magnify(CGFloat); case scroll(CGFloat) }` = an enum with **associated values** (a discriminated union carrying a payload).
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

**TypeScript equivalent**

```ts
// computed view property → a getter / derived value
get slide(): Slide | undefined {
  if (this.slideID != null) {
    const match = item.orderedSlides.find((s) => s.persistentModelID === this.slideID);
    if (match) return match;              // chained `if let slideID, let match`
  }
  return item.orderedSlides[0];           // fall back to the first slide
}

get selectedElement(): SlideElement | undefined {
  // slide?.orderedElements → optional chaining (undefined if no slide)
  return this.slide?.orderedElements.find((e) => e.persistentModelID === this.selection);
}
```

**Swift syntax:**
- `private var slide: Slide? { … }` — a **computed property** that returns an optional (`Slide?` = `Slide | undefined`). TS analog: a getter / derived value.
- `if let slideID, let match = item.orderedSlides.first(where: { … }) { … }` — chained optional binding; `first(where:)` returns `Element?`. TS analog: `if (slideID != null) { const match = arr.find(…); if (match) … }`.
- `slide?.orderedElements.first { … }` — `?.` skips to `nil` if `slide` is nil; `.first { … }` is `first(where:)` with a trailing closure. TS analog: `slide?.orderedElements.find(…)`.

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

**TypeScript equivalent**

```tsx
// VStack → <Column>; HSplitView → a draggable horizontal split
<Column spacing={0}>
  <HSplitView>
    <Pane minWidth={204} idealWidth={255} maxWidth={374}>{contentRail}</Pane>

    {slide ? (                                  // if let slide { … } else { placeholder }
      editorMode === "edit" ? (
        <>
          <Pane minWidth={520} minHeight={360}>{canvasArea(slide)}</Pane>
          <Pane minWidth={238} idealWidth={272} maxWidth={340}>
            <SlideInspectorView item={item} slide={slide} selectedElement={selectedElement} />
          </Pane>
        </>
      ) : (
        <Pane minWidth={520} minHeight={360}>{showStage(slide)}</Pane>
      )
    ) : (
      placeholder
    )}
  </HSplitView>

  {/* $snapToGrid → pass the [value, setValue] binding so the toggle flips OUR state */}
  <SlideStatusBar
    aspectLabel={aspectLabel}
    pixelSize={outputPixelSize}
    snapToGrid={[snapToGrid, setSnapToGrid]}
    showGuides={[showGuides, setShowGuides]}
    showSafeArea={[showSafeArea, setShowSafeArea]}
    zoom={zoom}
  />
</Column>
```

**Swift syntax:**
- `HSplitView { … }` / `VStack { … }` — container views; `HSplitView` is a draggable horizontal split. TS analog: a split-pane component / `<Column>`.
- `if let slide { … } else { … }` — **shorthand optional binding** (Swift 5.7+): `if let slide` unwraps `self.slide` into a same-named non-optional `slide`. TS analog: `{ slide ? … : … }`.
- `$snapToGrid` — the **binding form** of a `@State` var; passing it lets the child write back. TS analog: passing the `[value, setValue]` pair.
- `.frame(minWidth: 204, idealWidth: 255, maxWidth: 374)` — size constraints. TS analog: CSS min/ideal/max widths.

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

**TypeScript equivalent**

```tsx
// Modifiers stack onto the view; here they're effects/props on the returned tree.
useEffect(() => {                           // .onAppear { … }
  if (modelContext.undoManager == null) modelContext.undoManager = new UndoManager();
  setSelection(null);
  installZoomMonitor();
  return removeZoomMonitor;                 // .onDisappear(perform: removeZoomMonitor)
}, []);

useEffect(() => {                           // .onReceive(zoomInput) { applyZoom($0) }
  const sub = zoomInput.subscribe((input) => applyZoom(input));
  return () => sub.unsubscribe();
}, []);

useEffect(() => {                           // .onChange(of: slideID)
  setSelection(null);
  setInlineEditTarget(null);
}, [slideID]);

useEffect(() => {                           // .onChange(of: editorMode)
  setInlineEditTarget(null);
}, [editorMode]);

// .toolbar / .navigationTitle / .background(...) → toolbar + title + invisible overlays
```

**Swift syntax:**
- `.onAppear { … }` / `.onDisappear(perform: removeZoomMonitor)` — mount/unmount effects; `perform:` takes a function reference instead of a closure. TS analog: a `useEffect` with `[]` deps + its cleanup.
- `.onChange(of: slideID) { _, _ in … }` — runs when `slideID` changes; the closure gets `(oldValue, newValue)`, both ignored here via `_`. TS analog: `useEffect(…, [slideID])`.
- `.onReceive(zoomInput) { applyZoom($0) }` — subscribe to a Combine publisher; `$0` is the emitted value. TS analog: subscribing to an observable.
- `modelContext.undoManager == nil` / `= UndoManager()` — undo is **opt-in**; assigning a manager turns ⌘Z on. TS analog: lazily creating it if absent.
- `.navigationTitle(item.title.isEmpty ? "Edit Slide" : item.title)` — ternary. TS analog: identical `?:`.

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

**TypeScript equivalent**

```ts
// analogy: NSEvent local monitor → a window-scoped DOM listener for pinch + ⌘-scroll.
// Return null = consume the event; return event = let it pass (plain scroll still pans).
zoomMonitor = addLocalMonitor(["magnify", "scrollWheel"], (event) => {
  if (event.window !== windowRef.window) return event;   // guard … else { return event }: only THIS window
  switch (event.type) {
    case "magnify":
      input.send({ kind: "magnify", value: event.magnification });
      return null;                                        // consume
    case "scrollWheel":
      if (event.modifierFlags.includes("command")) {      // `where` clause → an extra condition
        const scale = event.hasPreciseScrollingDeltas ? 0.004 : 0.04;
        input.send({ kind: "scroll", value: event.scrollingDeltaY * scale });
        return null;
      }
      return event;                                       // ⌘ not held → pass through
    default:
      return event;                                       // pass through → stage pans
  }
});
```

**Swift syntax:**
- `guard event.window === windowRef.window else { return event }` — `===` is **reference identity** (same object), not value equality; the guard bails (returning the event unconsumed) unless it's this window. TS analog: `if (event.window !== …) return event;`.
- `case .scrollWheel where event.modifierFlags.contains(.command):` — a **`where` clause** on a `switch` case: the case matches only if the extra condition also holds. TS analog: a nested `if` inside the `case`.
- `input.send(.magnify(event.magnification))` — constructs the enum case `ZoomInput.magnify(_)` with its **associated value** and sends it. TS analog: `input.send({ kind: "magnify", value: … })`.
- `MainActor.assumeIsolated { … }` — asserts the closure runs on the main actor (main thread), letting it touch main-actor state without `await`. No direct TS analog (JS is single-threaded).
- `event.hasPreciseScrollingDeltas ? 0.004 : 0.04` — ternary picking the scroll scale. TS analog: identical.

Events go into the `zoomInput` Combine subject; `.onReceive(zoomInput)` calls `applyZoom`, which delegates the actual clamping/math to `CanvasZoomMath` (see `ZoomBar.md`). Returning `nil` consumes the event; returning `event` lets it pass (so non-⌘ scroll still pans the canvas).

The `applyZoom` switch routes each case to the matching `CanvasZoomMath` entry point:

```swift
private func applyZoom(_ input: ZoomInput) {
    switch input {
    case .magnify(let m): zoom = CanvasZoomMath.applying(magnify: m, to: zoom)
    case .scroll(let d):  zoom = CanvasZoomMath.applying(scroll: d, to: zoom)
    }
}
```

**TypeScript equivalent**

```ts
function applyZoom(input: { kind: "magnify" | "scroll"; value: number }) {
  switch (input.kind) {
    case "magnify":                                    // case .magnify(let m) → destructure payload
      setZoom(CanvasZoomMath.applyingMagnify(input.value, zoom));
      break;
    case "scroll":                                     // case .scroll(let d)
      setZoom(CanvasZoomMath.applyingScroll(input.value, zoom));
      break;
  }
}
```

**Swift syntax:**
- `case .magnify(let m):` — **`case let` binding**: matches the `magnify` case *and* extracts its associated value into `m`. TS analog: `case "magnify": const m = input.value`.

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

**TypeScript equivalent**

```tsx
function canvasArea(slide: Slide) {
  const aspect = item.aspectRatioValue;
  const canvasHeight = 760 / aspect;
  const pixelCanvas = { width: 760 * zoom, height: canvasHeight * zoom };

  return (
    <Layered>
      <EditorDeskBackdrop />                              {/* the dot-pattern desk */}
      <ScrollView axes={["horizontal", "vertical"]} defaultAnchor="center">
        <Layered
          style={{
            width: pixelCanvas.width,
            height: pixelCanvas.height,
            // pasteboard margin so off-slide handles stay reachable
            paddingInline: pixelCanvas.width * SlideGeometry.pasteboardMargin,
            paddingBlock: pixelCanvas.height * SlideGeometry.pasteboardMargin,
          }}
        >
          <SlideCanvasView
            slide={slide}
            selection={[selection, setSelection]}          // $selection
            snapToGrid={snapToGrid}
            showSafeArea={showSafeArea}
            showGuides={showGuides}
            aspectRatio={aspect}
            toastCenter={toastCenter}
            onInlineEditRequest={(element) => {            // trailing-closure prop
              setInlineEditCanvasSize(pixelCanvas);
              setInlineEditTarget(element);
            }}
            onDuplicate={duplicate}
            onDelete={delete}
          />
          {inlineEditTarget &&                             // if let element = inlineEditTarget, still-exists
            slide.orderedElements.some((e) => e.persistentModelID === inlineEditTarget.persistentModelID) &&
            inlineEditOverlay(inlineEditTarget, slide, pixelCanvas)}
        </Layered>
      </ScrollView>
      <EditorToast center={toastCenter} />
      {/* overlay bottom-leading */}
      <div style={{ position: "absolute", left: 14, bottom: 14 }}>
        <ZoomBar zoom={[zoom, setZoom]} />
      </div>
    </Layered>
  );
}
```

**Swift syntax:**
- `private func canvasArea(for slide: Slide) -> some View` — a method returning view content; `for slide:` is an external label. TS analog: `function canvasArea(slide)`.
- `ScrollView([.horizontal, .vertical]) { … }` — a 2-axis scroll container. TS analog: an overflow-auto box.
- `onInlineEditRequest: { element in … }` — a **trailing-closure-as-prop**; `{ element in … }` is the closure (`in` separates the param). TS analog: `onInlineEditRequest={(element) => …}`.
- `if let element = inlineEditTarget, slide.orderedElements.contains(where: { … })` — optional binding + an extra condition. TS analog: `inlineEditTarget && arr.some(…)`.
- `.overlay(alignment: .bottomLeading) { … }` — floats content over the view, pinned bottom-left. TS analog: an absolutely-positioned child.

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

**TypeScript equivalent**

```tsx
// fontSize is points at the 1920×1080 reference, so scale by canvasHeight / referenceHeight.
const scaledSize = (element.fontSize * canvasSize.height) / SlideRenderer.referenceHeight;
const font = {
  family: element.fontName,
  size: scaledSize,
  weight: element.isBold ? "bold" : "regular",
  italic: element.isItalic,
};

return (
  <InlineTextEditOverlay
    initialText={element.text ?? ""}                    // ?? "" — nil → empty string
    frame={rect}
    font={font}
    onCommit={(newText) => {
      if (newText !== (element.text ?? "")) {
        element.text = newText;
        slide.isManuallyEdited = true;
      }
      setInlineEditTarget(null);
    }}
    onCancel={() => setInlineEditTarget(null)}
  />
);
```

**Swift syntax:**
- `element.text ?? ""` — `??` substitutes `""` when `text` (a `String?`) is nil. TS analog: `element.text ?? ""`.
- `element.isBold ? .bold : .regular` / `element.isItalic ? baseFont.italic() : baseFont` — ternaries; `.bold`/`.regular` are leading-dot enum cases. TS analog: identical `?:`.
- `onCommit: { newText in … }` — a closure prop; `newText in` names the param. TS analog: `onCommit={(newText) => …}`.

Note `fontSize` is points at the 1920×1080 reference, so it's scaled by `canvasSize.height / SlideRenderer.referenceHeight` to match what's on screen. Committing writes `element.text` and marks the slide edited.

### Keyboard shortcuts and the toolbar

`keyboardShortcuts` is a clever trick: a `ZStack` of **invisible, zero-size buttons**, each bound to a shortcut, used purely to register ⌘Z / ⌘⇧Z (undo/redo), ⌘D (duplicate), and ⌘B/I/U (toggle bold/italic/underline on the selected text). Disabled buttons don't fire, which gates the shortcuts contextually. Delete is *deliberately not* a global shortcut (⌘⌫ collides with text-field editing) — it lives on the canvas right-click menu instead.

```swift
private func toggleStyle(_ keyPath: ReferenceWritableKeyPath<SlideElement, Bool>) {
    guard let element = selectedElement, element.kind == .text else { return }
    element[keyPath: keyPath].toggle()
    slide?.isManuallyEdited = true
}
```

**TypeScript equivalent**

```ts
// ReferenceWritableKeyPath<SlideElement, boolean> → a typed key naming a boolean field.
function toggleStyle(key: "isBold" | "isItalic" | "isUnderlined") {
  const element = selectedElement;
  if (element == null || element.kind !== "text") return;  // guard … else { return }
  element[key] = !element[key];                            // element[keyPath: key].toggle()
  if (slide != null) slide.isManuallyEdited = true;        // slide?.isManuallyEdited = true
}
```

**Swift syntax:**
- `ReferenceWritableKeyPath<SlideElement, Bool>` — a **key path** value naming a *settable* `Bool` property of `SlideElement`; passing `\.isBold` lets one function toggle any boolean field, type-checked. TS analog: a `keyof`-style string key (`"isBold" | …`).
- `element[keyPath: keyPath].toggle()` — read/write the property the key path points at; `.toggle()` flips a `Bool` in place. TS analog: `element[key] = !element[key]`.
- `guard let element = selectedElement, element.kind == .text else { return }` — optional binding + condition or bail. TS analog: `if (!element || element.kind !== "text") return`.
- `slide?.isManuallyEdited = true` — **optional-chaining assignment**: writes only if `slide` is non-nil. TS analog: `if (slide) slide.isManuallyEdited = true`.

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

**TypeScript equivalent**

```ts
function addText() {
  const slide = this.slide;
  if (slide == null) return;                              // guard let slide else { return }

  const element = new SlideElement({ kind: "text", order: nextOrder(slide), text: "Type here…" });
  (item.theme ?? Theme.makeDefault()).apply(element);     // ?? — default theme if none
  // default frame in NORMALIZED 0…1: ~centered, two-thirds wide
  element.x = 0.10; element.y = 0.40; element.width = 0.80; element.height = 0.20;

  modelContext.insert(element);                           // register with the SwiftData session
  slide.elements.push(element);                           // append to the ordered relationship
  slide.isManuallyEdited = true;                          // yield the rebuilder
  setSelection(element.persistentModelID);                // select the new element
}
```

**Swift syntax:**
- `guard let slide else { return }` — shorthand guard; bail unless `self.slide` is non-nil. TS analog: `if (slide == null) return`.
- `(item.theme ?? Theme.makeDefault()).apply(to: element)` — `??` picks a fallback theme, then `.apply(to:)` styles the element. TS analog: `(item.theme ?? Theme.makeDefault()).apply(element)`.
- `modelContext.insert(element)` / `slide.elements.append(element)` — register with the SwiftData session, then append to the ordered relationship. TS analog: `insert` + `array.push`.
- `element.x = 0.10; element.y = 0.40; …` — multiple statements on one line separated by `;`. TS analog: same.

`addShape`/`addImage` are siblings (`addImage` uses an `NSOpenPanel` + `MediaStorage.importFile` to copy the picked file into app storage). `duplicate` deep-copies every styling field and offsets the copy by `0.04` (capped at `0.9` via `min`). `delete` removes from the relationship, calls `modelContext.delete`, and clears selection/inline-edit if they pointed at it. `addBlankSlide` appends a themed `Slide` at the next order (`(item.slides.map(\.order).max() ?? -1) + 1`). Every one ends by flipping `isManuallyEdited`.

```swift
private func nextOrder(in slide: Slide) -> Int {
    (slide.elements.map(\.order).max() ?? -1) + 1
}
```

**TypeScript equivalent**

```ts
function nextOrder(slide: Slide): number {
  // map(\.order) → pluck the order field; max() is optional (empty → nil), so ?? -1
  const orders = slide.elements.map((e) => e.order);
  const max = orders.length ? Math.max(...orders) : null;
  return (max ?? -1) + 1;
}
```

**Swift syntax:**
- `slide.elements.map(\.order)` — `map` with a **key-path shorthand** `\.order` (pluck that field). TS analog: `arr.map(e => e.order)`.
- `.max() ?? -1` — `.max()` returns `Int?` (`nil` for an empty array), so `?? -1` defaults it. TS analog: `arr.length ? Math.max(...arr) : -1`.

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
