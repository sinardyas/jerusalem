import SwiftUI
import SwiftData
import AppKit
import Combine
import UniformTypeIdentifiers

/// Phase 8 slide editor sheet — the WYSIWYG composition view from MVP §3.2.
/// Opens for a single ``Slide`` from the slide grid (Edit mode). The canvas
/// edits the live model, so the operator window's grid + the audience output
/// reflect changes immediately (subject to the live/edit snapshot rule).
///
/// Phase 8.2.1 turned this from a one-slide modal into a 3-pane sheet —
/// `navigator | stage | inspector` — so all the parent item's slides are
/// reachable without dismissing back to the grid.
struct SlideEditorView: View {
    @Bindable var item: Item
    /// The slide currently being designed. Optional because the editor opens on
    /// an *item* (Phase 8.5) — a brand-new song has no slides yet; the operator
    /// types lyrics in the content rail and ``ContentRebuilder`` materializes them.
    @State var slideID: PersistentIdentifier?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var selection: PersistentIdentifier? = nil
    @State private var snapToGrid: Bool = true
    @State private var showSafeArea: Bool = true
    @State private var showGuides: Bool = true
    @State private var zoom: CGFloat = 1.0
    @State private var toastCenter = EditorToastCenter()
    @State private var inlineEditTarget: SlideElement? = nil
    @State private var inlineEditCanvasSize: CGSize = .zero
    @State private var editorMode: EditorMode = .edit

    // Trackpad pinch + ⌘-scroll zoom. An AppKit event monitor (SwiftUI has no
    // scroll-wheel handler) bridges deltas through `zoomInput` into `zoom`,
    // scoped to *this* editor window via `editorWindowRef`.
    @State private var editorWindowRef = WindowRef()
    @State private var zoomMonitor: Any? = nil
    @State private var zoomInput = PassthroughSubject<ZoomInput, Never>()
    private enum ZoomInput { case magnify(CGFloat); case scroll(CGFloat) }

    /// The toolbar's Show/Edit segmented control (prototype). `Edit` is the
    /// composition canvas; `Show` is a clean audience-style preview.
    enum EditorMode: String, CaseIterable, Identifiable {
        case show = "Show", edit = "Edit"
        var id: String { rawValue }
    }

    private var slide: Slide? {
        if let slideID, let match = item.orderedSlides.first(where: { $0.persistentModelID == slideID }) {
            return match
        }
        return item.orderedSlides.first
    }

    private var selectedElement: SlideElement? {
        slide?.orderedElements.first { $0.persistentModelID == selection }
    }

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                contentRail
                    .frame(minWidth: 204, idealWidth: 255, maxWidth: 374)
                if let slide {
                    if editorMode == .edit {
                        canvasArea(for: slide)
                            .frame(minWidth: 520, minHeight: 360)
                        SlideInspectorView(item: item, slide: slide, selectedElement: selectedElement)
                            .frame(minWidth: 238, idealWidth: 272, maxWidth: 340)
                    } else {
                        showStage(for: slide)
                            .frame(minWidth: 520, minHeight: 360)
                    }
                } else {
                    placeholder
                }
            }
            SlideStatusBar(aspectLabel: aspectLabel,
                           pixelSize: outputPixelSize,
                           snapToGrid: $snapToGrid,
                           showGuides: $showGuides,
                           showSafeArea: $showSafeArea,
                           zoom: zoom)
        }
        .toolbar { toolbarContent }
        .navigationTitle(item.title.isEmpty ? "Edit Slide" : item.title)
        .navigationSubtitle(editorMode == .show ? "presenting" : "editing")
        .background(keyboardShortcuts)
        .background(WindowAccessor { editorWindowRef.window = $0 })
        .frame(minWidth: 1080, minHeight: 640)
        .onReceive(zoomInput) { applyZoom($0) }
        .onAppear {
            // Enable undo on the editor's context — undoManager is opt-in on
            // SwiftData and survives view appearances. The shared main context's
            // tracking covers every property write the editor makes.
            if modelContext.undoManager == nil {
                modelContext.undoManager = UndoManager()
            }
            // Clear stale element selection when the editor swaps which slide is
            // the target (so a handle from the previous slide doesn't linger).
            selection = nil
            installZoomMonitor()
        }
        .onDisappear(perform: removeZoomMonitor)
        .onChange(of: slideID) { _, _ in
            selection = nil
            inlineEditTarget = nil
        }
        // Leaving edit mode (or returning to it) must not resurrect a half-open
        // inline text editor for the previously-tapped element.
        .onChange(of: editorMode) { _, _ in inlineEditTarget = nil }
    }

    // MARK: - Pinch / ⌘-scroll zoom

    private func applyZoom(_ input: ZoomInput) {
        switch input {
        case .magnify(let m): zoom = CanvasZoomMath.applying(magnify: m, to: zoom)
        case .scroll(let d):  zoom = CanvasZoomMath.applying(scroll: d, to: zoom)
        }
    }

    /// Local monitor for trackpad pinch (`.magnify`) and ⌘-scroll (`.scrollWheel`
    /// with Command). Scoped to events that occur in *this* editor window, so it
    /// never zooms a different window's canvas; plain scroll passes through so the
    /// stage still pans.
    private func installZoomMonitor() {
        guard zoomMonitor == nil else { return }
        let windowRef = editorWindowRef
        let input = zoomInput
        zoomMonitor = NSEvent.addLocalMonitorForEvents(matching: [.magnify, .scrollWheel]) { event in
            MainActor.assumeIsolated {
                guard event.window === windowRef.window else { return event }
                switch event.type {
                case .magnify:
                    input.send(.magnify(event.magnification))
                    return nil
                case .scrollWheel where event.modifierFlags.contains(.command):
                    let scale: CGFloat = event.hasPreciseScrollingDeltas ? 0.004 : 0.04
                    input.send(.scroll(event.scrollingDeltaY * scale))
                    return nil
                default:
                    return event
                }
            }
        }
    }

    private func removeZoomMonitor() {
        if let zoomMonitor { NSEvent.removeMonitor(zoomMonitor) }
        zoomMonitor = nil
    }

    /// Left rail: three vertically-split sections that divide the rail height
    /// proportionally — content authoring (title + lyrics/reference/body), the
    /// slide navigator, and the Layers panel for the current slide. Content
    /// authoring reuses the per-kind editors (which debounce → ``ContentRebuilder``
    /// → `live.arm`, so slides regenerate live as you type). Layers lives here
    /// (not the right inspector) so selecting an object doesn't reshuffle it.
    private var contentRail: some View {
        VSplitView {
            itemContentEditor
                .frame(minHeight: 140, idealHeight: 240)
            SlideNavigatorView(item: item,
                               selection: $slideID,
                               onAddSlide: addBlankSlide)
                .frame(minHeight: 110, idealHeight: 180)
            if let slide {
                SlideLayersSection(slide: slide,
                                   selection: $selection,
                                   onDelete: delete,
                                   onChange: { slide.isManuallyEdited = true })
                    .frame(minHeight: 110, idealHeight: 180)
            }
        }
    }

    @ViewBuilder private var itemContentEditor: some View {
        switch item.kind {
        case .song:  SongEditorView(item: item)
        case .text:  SermonEditorView(item: item)
        case .bible: BibleEditorView(item: item)
        case .media: Form { VideoSettingsSection(item: item) }.formStyle(.grouped)
        }
    }

    /// Invisible buttons that bind keyboard shortcuts. Undo/redo hit the
    /// SwiftData undo manager; `⌘D` duplicates the selected element. Delete is
    /// intentionally *not* a global shortcut — `⌘⌫` collides with "delete to
    /// start of line" in the inspector text fields, so deleting lives on the
    /// canvas element's right-click menu. Disabled buttons don't fire shortcuts.
    private var keyboardShortcuts: some View {
        ZStack {
            Button { modelContext.undoManager?.undo() } label: { Color.clear }
                .keyboardShortcut("z", modifiers: [.command])
            Button { modelContext.undoManager?.redo() } label: { Color.clear }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            Button { duplicateSelection() } label: { Color.clear }
                .keyboardShortcut("d", modifiers: [.command])
                .disabled(editorMode == .show || selectedElement == nil)
            // Standard text-style shortcuts for the selected text object — work
            // while it's selected or being inline-edited (a plain editor doesn't
            // consume ⌘B/I/U), so you can style as you type.
            Button { toggleStyle(\.isBold) } label: { Color.clear }
                .keyboardShortcut("b", modifiers: [.command])
                .disabled(styleShortcutsDisabled)
            Button { toggleStyle(\.isItalic) } label: { Color.clear }
                .keyboardShortcut("i", modifiers: [.command])
                .disabled(styleShortcutsDisabled)
            Button { toggleStyle(\.isUnderlined) } label: { Color.clear }
                .keyboardShortcut("u", modifiers: [.command])
                .disabled(styleShortcutsDisabled)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }

    private var styleShortcutsDisabled: Bool {
        editorMode == .show || selectedElement?.kind != .text
    }

    /// Toggles a boolean style on the selected text element (⌘B/⌘I/⌘U).
    private func toggleStyle(_ keyPath: ReferenceWritableKeyPath<SlideElement, Bool>) {
        guard let element = selectedElement, element.kind == .text else { return }
        element[keyPath: keyPath].toggle()
        slide?.isManuallyEdited = true
    }

    private var placeholder: some View {
        ContentUnavailableView("No Slides Yet",
                               systemImage: "rectangle.on.rectangle.slash",
                               description: Text("Type content in the left rail (it generates slides automatically), or add a blank slide with the + button."))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The canvas, the dot-pattern desk behind it, and the snap-feedback toast.
    private func canvasArea(for slide: Slide) -> some View {
        let aspect = item.aspectRatioValue
        let canvasHeight = 760 / aspect
        return ZStack {
            EditorDeskBackdrop()
                .ignoresSafeArea()
            ScrollView([.horizontal, .vertical]) {
                ZStack {
                    SlideCanvasView(slide: slide,
                                    selection: $selection,
                                    snapToGrid: snapToGrid,
                                    showSafeArea: showSafeArea,
                                    showGuides: showGuides,
                                    aspectRatio: aspect,
                                    toastCenter: toastCenter,
                                    onInlineEditRequest: { element in
                        inlineEditCanvasSize = CGSize(width: 760 * zoom, height: canvasHeight * zoom)
                        inlineEditTarget = element
                    },
                                    onDuplicate: duplicate,
                                    onDelete: delete)
                    if let element = inlineEditTarget,
                       slide.orderedElements.contains(where: { $0.persistentModelID == element.persistentModelID }) {
                        inlineEditOverlay(for: element, slide: slide,
                                          canvasSize: CGSize(width: 760 * zoom, height: canvasHeight * zoom))
                    }
                }
                .frame(width: 760 * zoom, height: canvasHeight * zoom)
                .padding(40)
            }
            EditorToast(center: toastCenter)
        }
        .overlay(alignment: .bottomLeading) {
            ZoomBar(zoom: $zoom).padding(14)
        }
    }

    /// Show mode: a clean, audience-style preview of the current slide — the
    /// same shared renderer, with none of the editing chrome (no desk, handles,
    /// guides, safe-area, or zoom). Reuses ``RenderableSlideView`` verbatim.
    private func showStage(for slide: Slide) -> some View {
        ZStack {
            Color.black
            RenderableSlideView(renderable: RenderableSlide(slide),
                                aspectRatio: item.aspectRatioValue)
                .aspectRatio(item.aspectRatioValue, contentMode: .fit)
                .padding(40)
        }
    }

    /// Floats the ``InlineTextEditOverlay`` over a text element's frame, sized
    /// to the *current* canvas pixel size so the editor matches what's on screen.
    private func inlineEditOverlay(for element: SlideElement,
                                   slide: Slide,
                                   canvasSize: CGSize) -> some View {
        let rect = CGRect(x: element.x * canvasSize.width,
                          y: element.y * canvasSize.height,
                          width: element.width * canvasSize.width,
                          height: element.height * canvasSize.height)
        let alignment: TextAlignment = {
            switch element.alignment {
            case .leading:   return .leading
            case .center:    return .center
            case .trailing:  return .trailing
            case .justified: return .leading   // SwiftUI Text doesn't justify
            }
        }()
        // WYSIWYG: the inline editor uses the element's actual font family,
        // weight, and italic — so typing on the slide matches the render.
        let scaledSize = element.fontSize * canvasSize.height / SlideRenderer.referenceHeight
        let baseFont = Font.custom(element.fontName, size: scaledSize)
            .weight(element.isBold ? .bold : .regular)
        let font = element.isItalic ? baseFont.italic() : baseFont
        return InlineTextEditOverlay(
            initialText: element.text ?? "",
            frame: rect,
            font: font,
            textColor: Color(hex: element.colorHex),
            alignment: alignment,
            onCommit: { newText in
                if newText != (element.text ?? "") {
                    element.text = newText
                    slide.isManuallyEdited = true
                }
                inlineEditTarget = nil
            },
            onCancel: { inlineEditTarget = nil })
    }

    private var aspectLabel: String { item.aspectRatio ?? "16:9" }

    /// The output's pixel resolution at the editor's reference aspect — the
    /// status bar shows this so the operator can spot a non-1920×1080 size at
    /// a glance.
    private var outputPixelSize: CGSize {
        let height: CGFloat = 1080
        return CGSize(width: height * item.aspectRatioValue, height: height)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Show / Edit (prototype's leftmost segmented control).
        ToolbarItem(placement: .navigation) {
            Picker("Mode", selection: $editorMode) {
                ForEach(EditorMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
        }
        // Object tools + Undo/Redo. Editing-only, so they disable in Show mode.
        ToolbarItemGroup(placement: .principal) {
            Button { addText() } label: { Label("Text", systemImage: "textformat") }
                .disabled(editorMode == .show)
            Button { addImage() } label: { Label("Image", systemImage: "photo") }
                .disabled(editorMode == .show)
            Button { addShape() } label: { Label("Shape", systemImage: "square.on.circle") }
                .disabled(editorMode == .show)
            // "Background" focuses the slide background by clearing the element
            // selection, so the inspector surfaces the Background section.
            Button { selection = nil } label: { Label("Background", systemImage: "photo.artframe") }
                .disabled(editorMode == .show)
            Divider()
            Button { modelContext.undoManager?.undo() } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }.disabled(editorMode == .show || !(modelContext.undoManager?.canUndo ?? false))
            Button { modelContext.undoManager?.redo() } label: {
                Label("Redo", systemImage: "arrow.uturn.forward")
            }.disabled(editorMode == .show || !(modelContext.undoManager?.canRedo ?? false))
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Picker("Aspect", selection: Binding(
                get: { item.aspectRatio ?? "16:9" },
                set: { item.aspectRatio = $0 })) {
                Text("16:9").tag("16:9")
                Text("4:3").tag("4:3")
            }
            .pickerStyle(.segmented)
            .frame(width: 120)
            Button("Done") { dismiss() }
                .keyboardShortcut(.return, modifiers: [.command])
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Slide actions

    /// Inserts a fresh blank slide at the end of the item, themed via
    /// `item.theme` (falling back to the default if the item never got one).
    private func addBlankSlide() {
        let theme = item.theme ?? Theme.makeDefault()
        if item.theme == nil { item.theme = theme }
        let nextOrder = (item.slides.map(\.order).max() ?? -1) + 1
        let slide = Slide(order: nextOrder)
        theme.apply(to: slide)
        slide.isManuallyEdited = true
        modelContext.insert(slide)
        item.slides.append(slide)
        slideID = slide.persistentModelID
    }

    // MARK: - Element actions

    private func addText() {
        guard let slide else { return }
        let element = SlideElement(kind: .text, order: nextOrder(in: slide), text: "Type here…")
        (item.theme ?? Theme.makeDefault()).apply(to: element)
        // Default frame: roughly centered, two-thirds wide.
        element.x = 0.10; element.y = 0.40; element.width = 0.80; element.height = 0.20
        modelContext.insert(element)
        slide.elements.append(element)
        slide.isManuallyEdited = true
        selection = element.persistentModelID
    }

    private func addShape() {
        guard let slide else { return }
        let element = SlideElement(kind: .shape, order: nextOrder(in: slide))
        element.shapeType = .rectangle
        element.fillColorHex = "#3B82F6"
        element.x = 0.30; element.y = 0.30; element.width = 0.40; element.height = 0.30
        modelContext.insert(element)
        slide.elements.append(element)
        slide.isManuallyEdited = true
        selection = element.persistentModelID
    }

    private func addImage() {
        guard let slide else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let filename = try MediaStorage.importFile(at: url)
            let element = SlideElement(kind: .image, order: nextOrder(in: slide))
            element.imageFilename = filename
            element.x = 0.20; element.y = 0.20; element.width = 0.60; element.height = 0.50
            modelContext.insert(element)
            slide.elements.append(element)
            slide.isManuallyEdited = true
            selection = element.persistentModelID
        } catch {
            NSSound.beep()
        }
    }

    private func duplicateSelection() {
        if let element = selectedElement { duplicate(element) }
    }

    private func duplicate(_ original: SlideElement) {
        guard let slide else { return }
        let copy = SlideElement(kind: original.kind, order: nextOrder(in: slide), text: original.text)
        copy.x = min(0.9, original.x + 0.04)
        copy.y = min(0.9, original.y + 0.04)
        copy.width = original.width
        copy.height = original.height
        copy.fontName = original.fontName
        copy.fontSize = original.fontSize
        copy.colorHex = original.colorHex
        copy.alignment = original.alignment
        copy.isBold = original.isBold
        copy.isItalic = original.isItalic
        copy.hasShadow = original.hasShadow
        copy.hasStroke = original.hasStroke
        copy.autoFit = original.autoFit
        copy.imageFilename = original.imageFilename
        copy.shapeType = original.shapeType
        copy.fillColorHex = original.fillColorHex
        copy.cornerRadius = original.cornerRadius
        copy.strokeWidth = original.strokeWidth
        copy.strokeColorHex = original.strokeColorHex
        modelContext.insert(copy)
        slide.elements.append(copy)
        slide.isManuallyEdited = true
        selection = copy.persistentModelID
    }

    private func delete(_ element: SlideElement) {
        guard let slide else { return }
        slide.elements.removeAll { $0.persistentModelID == element.persistentModelID }
        modelContext.delete(element)
        if selection == element.persistentModelID { selection = nil }
        if inlineEditTarget?.persistentModelID == element.persistentModelID { inlineEditTarget = nil }
        slide.isManuallyEdited = true
    }

    private func nextOrder(in slide: Slide) -> Int {
        (slide.elements.map(\.order).max() ?? -1) + 1
    }
}
