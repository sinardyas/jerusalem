import SwiftUI
import SwiftData

/// Pure z-order math for the Layers panel — extracted so it's unit-testable
/// without UI. Mirrors ``SlideArrangeSection``'s "rewrite `order` from positions"
/// approach, applied to a front-first drag reorder.
enum SlideLayers {
    /// Applies a SwiftUI front-first layer-list move and rewrites each element's
    /// `order` so the back-most gets 0 and the front-most gets `count - 1`.
    static func reorder(frontFirst elements: [SlideElement],
                        from source: IndexSet, to destination: Int) {
        var arr = elements
        arr.move(fromOffsets: source, toOffset: destination)
        let count = arr.count
        for (index, element) in arr.enumerated() {
            element.order = count - 1 - index
        }
    }
}

/// Left-rail "Layers" panel (Phase 8.7): a draggable list of the current slide's
/// objects, front at top. Drag to restack (the renderer draws strictly by
/// `order`), click to select (synced with the canvas), and remove via the
/// per-row trash button or the Delete key. Living in the left rail (not the
/// right inspector) means selecting an object doesn't reshuffle the panel — and,
/// since it's no longer nested inside the inspector's `ScrollView`, the list
/// scrolls/selects natively without dragging the sidebar around.
struct SlideLayersSection: View {
    @Bindable var slide: Slide
    @Binding var selection: PersistentIdentifier?
    var onDelete: (SlideElement) -> Void
    var onChange: () -> Void

    /// Front-most first — the list reads top→bottom as front→back.
    private var layers: [SlideElement] { Array(slide.orderedElements.reversed()) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Layers").font(.headline)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            Divider()

            if slide.elements.isEmpty {
                ContentUnavailableView("No Objects",
                                       systemImage: "square.3.layers.3d.slash",
                                       description: Text("Add a text, image, or shape from the toolbar."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selection) {
                    ForEach(layers, id: \.persistentModelID) { element in
                        LayerRow(element: element) { onDelete(element) }
                            .tag(element.persistentModelID as PersistentIdentifier?)
                    }
                    .onMove { source, destination in
                        SlideLayers.reorder(frontFirst: layers, from: source, to: destination)
                        onChange()
                    }
                }
                .listStyle(.sidebar)
                .onDeleteCommand(perform: deleteSelected)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func deleteSelected() {
        guard let selection,
              let element = slide.elements.first(where: { $0.persistentModelID == selection })
        else { return }
        onDelete(element)
    }
}

/// One row in the Layers list: a kind glyph, the object's name, and a trash button.
private struct LayerRow: View {
    let element: SlideElement
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: glyph.symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(glyph.color, in: RoundedRectangle(cornerRadius: 4))
            Text(element.layerName)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete this object")
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    /// Mirrors ``InspectorHeaderChip``'s per-kind glyph + color.
    private var glyph: (symbol: String, color: Color) {
        switch element.kind {
        case .text:  return ("textformat", .orange)
        case .image: return ("photo", .blue)
        case .shape: return ("square.on.circle", .purple)
        }
    }
}
