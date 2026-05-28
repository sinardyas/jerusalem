import SwiftUI
import SwiftData
import AppKit
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
    @State var slideID: PersistentIdentifier
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

    private var slide: Slide? {
        item.orderedSlides.first { $0.persistentModelID == slideID }
            ?? item.orderedSlides.first
    }

    private var selectedElement: SlideElement? {
        slide?.orderedElements.first { $0.persistentModelID == selection }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HSplitView {
                    SlideNavigatorView(item: item,
                                       selection: Binding(get: { slideID },
                                                          set: { if let id = $0 { slideID = id } }),
                                       onAddSlide: addBlankSlide)
                        .frame(minWidth: 180, idealWidth: 220, maxWidth: 300)
                    if let slide {
                        canvasArea(for: slide)
                            .frame(minWidth: 520, minHeight: 360)
                        SlideInspectorView(item: item, slide: slide, selectedElement: selectedElement)
                            .frame(minWidth: 280, idealWidth: 320, maxWidth: 400)
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
            .background(undoShortcuts)
        }
        .frame(minWidth: 1080, minHeight: 640)
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
        }
        .onChange(of: slideID) { _, _ in selection = nil }
    }

    /// Invisible buttons that bind `⌘Z` / `⇧⌘Z` to the SwiftData undo manager.
    /// Hidden via `Color.clear` so they never paint anything; the keyboard
    /// shortcuts still register because the buttons are in the view hierarchy.
    private var undoShortcuts: some View {
        ZStack {
            Button { modelContext.undoManager?.undo() } label: { Color.clear }
                .keyboardShortcut("z", modifiers: [.command])
            Button { modelContext.undoManager?.redo() } label: { Color.clear }
                .keyboardShortcut("z", modifiers: [.command, .shift])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }

    private var placeholder: some View {
        ContentUnavailableView("No Slide Selected",
                               systemImage: "rectangle.on.rectangle.slash",
                               description: Text("Add a slide from the navigator to begin editing."))
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
                    })
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
        return InlineTextEditOverlay(
            initialText: element.text ?? "",
            frame: rect,
            font: Font.system(size: element.fontSize * canvasSize.height / SlideRenderer.referenceHeight,
                              weight: element.isBold ? .bold : .regular)
                .italic(),
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
        ToolbarItemGroup(placement: .principal) {
            Button { addText() } label: { Label("Text", systemImage: "textformat") }
                .disabled(slide == nil)
            Button { addImage() } label: { Label("Image", systemImage: "photo") }
                .disabled(slide == nil)
            Divider()
            Button { duplicateSelection() } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }.disabled(selectedElement == nil)
            Button { deleteSelection() } label: {
                Label("Delete", systemImage: "trash")
            }.disabled(selectedElement == nil)
            Divider()
            Button { reorder(.raise) } label: {
                Label("Bring Forward", systemImage: "square.3.layers.3d.top.filled")
            }.disabled(selectedElement == nil)
            Button { reorder(.lower) } label: {
                Label("Send Backward", systemImage: "square.3.layers.3d.bottom.filled")
            }.disabled(selectedElement == nil)
            Divider()
            // Visible Undo/Redo — same SwiftData undoManager that ⌘Z / ⇧⌘Z hit.
            Button { modelContext.undoManager?.undo() } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }.disabled(!(modelContext.undoManager?.canUndo ?? false))
            Button { modelContext.undoManager?.redo() } label: {
                Label("Redo", systemImage: "arrow.uturn.forward")
            }.disabled(!(modelContext.undoManager?.canRedo ?? false))
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
            HStack(spacing: 6) {
                Image(systemName: "minus.magnifyingglass")
                Slider(value: $zoom, in: 0.5...2.0).frame(width: 100)
                Image(systemName: "plus.magnifyingglass")
            }
            Button("Done") { dismiss() }
                .keyboardShortcut(.return, modifiers: [.command])
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
        guard let slide, let original = selectedElement else { return }
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
        modelContext.insert(copy)
        slide.elements.append(copy)
        slide.isManuallyEdited = true
        selection = copy.persistentModelID
    }

    private func deleteSelection() {
        guard let slide, let element = selectedElement else { return }
        slide.elements.removeAll { $0.persistentModelID == element.persistentModelID }
        modelContext.delete(element)
        slide.isManuallyEdited = true
        selection = nil
    }

    private enum ReorderDirection { case raise, lower }

    private func reorder(_ direction: ReorderDirection) {
        guard let slide, let selected = selectedElement else { return }
        let ordered = slide.orderedElements
        guard let index = ordered.firstIndex(where: { $0.persistentModelID == selected.persistentModelID })
        else { return }
        switch direction {
        case .raise where index < ordered.count - 1:
            let neighbor = ordered[index + 1]
            (selected.order, neighbor.order) = (neighbor.order, selected.order)
        case .lower where index > 0:
            let neighbor = ordered[index - 1]
            (selected.order, neighbor.order) = (neighbor.order, selected.order)
        default: break
        }
        slide.isManuallyEdited = true
    }

    private func nextOrder(in slide: Slide) -> Int {
        (slide.elements.map(\.order).max() ?? -1) + 1
    }
}
