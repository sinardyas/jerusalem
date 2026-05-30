import SwiftUI
import SwiftData

/// The interactive WYSIWYG canvas. A rendered ``SlideView`` sits underneath an
/// overlay that draws selection handles, alignment guides, and a safe-area
/// outline; SwiftUI gestures translate user drags/resizes into normalized
/// 0…1 mutations on the SwiftData model.
///
/// Edits happen *on the live model* (the editor is a sheet, not a snapshot), so
/// the shared renderer's `View.task`-driven thumbnail/preview/output all reflect
/// edits as they happen.
struct SlideCanvasView: View {
    @Bindable var slide: Slide
    @Binding var selection: PersistentIdentifier?
    var snapToGrid: Bool
    var showSafeArea: Bool
    var showGuides: Bool = true
    var aspectRatio: CGFloat = 16.0 / 9.0
    var toastCenter: EditorToastCenter? = nil
    var onInlineEditRequest: ((SlideElement) -> Void)? = nil
    var onDuplicate: ((SlideElement) -> Void)? = nil
    var onDelete: ((SlideElement) -> Void)? = nil

    @State private var dragOrigin: SlideGeometry.Frame? = nil
    @State private var dragHandle: SlideGeometry.Handle? = nil
    @State private var activeVerticalGuide: Double? = nil
    @State private var activeHorizontalGuide: Double? = nil

    private var elements: [SlideElement] { slide.orderedElements }

    var body: some View {
        GeometryReader { geometry in
            let canvasSize = geometry.size
            ZStack {
                // 1. Base slide as rendered by the shared SlideRenderer.
                RenderableSlideView(renderable: RenderableSlide(slide), aspectRatio: aspectRatio)
                    .contentShape(Rectangle())
                    .onTapGesture { selection = nil }

                // 2. Safe-area overlay (5% inset, dashed) — toggleable.
                if showSafeArea {
                    Rectangle()
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(canvasSize.width * 0.05)
                        .allowsHitTesting(false)
                }

                // 3. Per-element selection overlay (in render order).
                ForEach(elements) { element in
                    elementOverlay(element, canvasSize: canvasSize)
                }

                // 4. Alignment guides drawn at whichever candidates we matched.
                if showGuides, let x = activeVerticalGuide {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 1, height: canvasSize.height)
                        .position(x: x * canvasSize.width, y: canvasSize.height / 2)
                        .allowsHitTesting(false)
                }
                if showGuides, let y = activeHorizontalGuide {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: canvasSize.width, height: 1)
                        .position(x: canvasSize.width / 2, y: y * canvasSize.height)
                        .allowsHitTesting(false)
                }
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
    }

    // MARK: - Element overlay

    @ViewBuilder
    private func elementOverlay(_ element: SlideElement, canvasSize: CGSize) -> some View {
        let isSelected = selection == element.persistentModelID
        let frame = SlideGeometry.Frame(
            x: element.x, y: element.y, width: element.width, height: element.height)
        let rect = CGRect(
            x: frame.x * canvasSize.width, y: frame.y * canvasSize.height,
            width: frame.width * canvasSize.width, height: frame.height * canvasSize.height)

        ZStack {
            // Invisible hit target = the element's body.
            Color.clear
                .contentShape(Rectangle())
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .gesture(dragGesture(for: element, handle: .body, canvasSize: canvasSize))
                .onTapGesture(count: 2) {
                    if element.kind == .text { onInlineEditRequest?(element) }
                }
                .onTapGesture {
                    selection = element.persistentModelID
                }
                .contextMenu {
                    Button("Duplicate") { onDuplicate?(element) }
                    Button("Delete", role: .destructive) { onDelete?(element) }
                }
            // Selection outline + 8 resize handles.
            if isSelected {
                Rectangle()
                    .strokeBorder(Color.accentColor, lineWidth: 1.5)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .allowsHitTesting(false)
                ForEach(Self.handles, id: \.position) { handle in
                    Self.handleView(handle: handle.kind, in: rect)
                        .gesture(dragGesture(for: element, handle: handle.kind, canvasSize: canvasSize))
                }
            }
        }
    }

    private struct HandleDescriptor: Hashable {
        let kind: SlideGeometry.Handle
        let position: String   // stable key for ForEach
    }
    private static let handles: [HandleDescriptor] = [
        .init(kind: .topLeft, position: "tl"),
        .init(kind: .top, position: "tm"),
        .init(kind: .topRight, position: "tr"),
        .init(kind: .left, position: "ml"),
        .init(kind: .right, position: "mr"),
        .init(kind: .bottomLeft, position: "bl"),
        .init(kind: .bottom, position: "bm"),
        .init(kind: .bottomRight, position: "br"),
    ]

    /// Filled-white square with a 1.5pt accent stroke and a 1pt corner radius —
    /// matches the prototype mockup so the canvas reads as a real editor stage.
    private static func handleView(handle: SlideGeometry.Handle, in rect: CGRect) -> some View {
        let p = handlePoint(handle, in: rect)
        return RoundedRectangle(cornerRadius: 1)
            .fill(Color.white)
            .overlay(RoundedRectangle(cornerRadius: 1)
                .strokeBorder(Color.accentColor, lineWidth: 1.5))
            .shadow(color: .black.opacity(0.25), radius: 1, x: 0, y: 1)
            .frame(width: 11, height: 11)
            .position(p)
    }

    private static func handlePoint(_ handle: SlideGeometry.Handle, in rect: CGRect) -> CGPoint {
        switch handle {
        case .topLeft:     return CGPoint(x: rect.minX, y: rect.minY)
        case .top:         return CGPoint(x: rect.midX, y: rect.minY)
        case .topRight:    return CGPoint(x: rect.maxX, y: rect.minY)
        case .left:        return CGPoint(x: rect.minX, y: rect.midY)
        case .right:       return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomLeft:  return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottom:      return CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .body:        return CGPoint(x: rect.midX, y: rect.midY)
        }
    }

    // MARK: - Gesture

    private func dragGesture(for element: SlideElement,
                             handle: SlideGeometry.Handle,
                             canvasSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragOrigin == nil {
                    selection = element.persistentModelID
                    dragOrigin = SlideGeometry.Frame(
                        x: element.x, y: element.y, width: element.width, height: element.height)
                    dragHandle = handle
                }
                guard let origin = dragOrigin, let activeHandle = dragHandle else { return }
                let dx = value.translation.width / canvasSize.width
                let dy = value.translation.height / canvasSize.height
                var next = SlideGeometry.dragged(origin, by: dx, dy: dy, handle: activeHandle)

                // Body drags snap to alignment candidates (slide center, other
                // elements' edges/centers); resizes only snap to the grid.
                if activeHandle == .body {
                    let candidates = SlideGeometry.alignmentCandidates(
                        against: elements
                            .filter { $0.persistentModelID != element.persistentModelID }
                            .map(Self.frame(of:)))
                    if let v = SlideGeometry.snapVertical(frame: next, candidates: candidates) {
                        next = adjusted(next, snappingVerticalAnchor: v.anchor, to: v.line)
                        activeVerticalGuide = v.line
                        toastCenter?.show(toastLabel(forVerticalLine: v.line, anchor: v.anchor))
                    } else {
                        activeVerticalGuide = nil
                    }
                    if let h = SlideGeometry.snapHorizontal(frame: next, candidates: candidates) {
                        next = adjusted(next, snappingHorizontalAnchor: h.anchor, to: h.line)
                        activeHorizontalGuide = h.line
                        toastCenter?.show(toastLabel(forHorizontalLine: h.line, anchor: h.anchor))
                    } else {
                        activeHorizontalGuide = nil
                    }
                }
                next = SlideGeometry.snappedToGrid(next, enabled: snapToGrid)
                next = SlideGeometry.clamped(next)

                element.x = next.x
                element.y = next.y
                element.width = next.width
                element.height = next.height
            }
            .onEnded { _ in
                dragOrigin = nil
                dragHandle = nil
                activeVerticalGuide = nil
                activeHorizontalGuide = nil
                slide.isManuallyEdited = true
            }
    }

    private func toastLabel(forVerticalLine line: Double, anchor: SlideGeometry.SnapAnchor) -> String {
        if abs(line - 0.5) < 1e-6 { return "Snapped to center" }
        if abs(line) < 1e-6 || abs(line - 1) < 1e-6 { return "Snapped to edge" }
        return "Snapped to element"
    }

    private func toastLabel(forHorizontalLine line: Double, anchor: SlideGeometry.SnapAnchor) -> String {
        if abs(line - 0.5) < 1e-6 { return "Snapped to center" }
        if abs(line) < 1e-6 || abs(line - 1) < 1e-6 { return "Snapped to edge" }
        return "Snapped to element"
    }

    // Translate a vertical snap-anchor result into a corrected frame.
    private func adjusted(_ frame: SlideGeometry.Frame,
                          snappingVerticalAnchor anchor: SlideGeometry.SnapAnchor,
                          to line: Double) -> SlideGeometry.Frame {
        var f = frame
        switch anchor {
        case .leading:  f.x = line
        case .center:   f.x = line - f.width / 2
        case .trailing: f.x = line - f.width
        }
        return f
    }
    private func adjusted(_ frame: SlideGeometry.Frame,
                          snappingHorizontalAnchor anchor: SlideGeometry.SnapAnchor,
                          to line: Double) -> SlideGeometry.Frame {
        var f = frame
        switch anchor {
        case .leading:  f.y = line
        case .center:   f.y = line - f.height / 2
        case .trailing: f.y = line - f.height
        }
        return f
    }

    fileprivate static func frame(of element: SlideElement) -> SlideGeometry.Frame {
        SlideGeometry.Frame(x: element.x, y: element.y, width: element.width, height: element.height)
    }
}
