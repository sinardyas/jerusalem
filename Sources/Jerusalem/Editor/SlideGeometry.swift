import Foundation

/// Pure geometry rules for the Phase 8 slide editor. Everything here works in
/// the renderer's normalized 0…1 coordinate space (top-left origin) so the
/// editor never has to know its on-screen pixel size — it converts at the
/// edges and lets this layer handle snap, clamp, and reorder.
///
/// Caseless `enum` per project convention so the math is unit-testable without
/// SwiftUI / AppKit / SwiftData.
enum SlideGeometry {

    /// A normalized element frame: x/y top-left, width/height in 0…1.
    struct Frame: Equatable, Sendable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double

        var minX: Double { x }
        var minY: Double { y }
        var maxX: Double { x + width }
        var maxY: Double { y + height }
        var centerX: Double { x + width / 2 }
        var centerY: Double { y + height / 2 }
    }

    /// One of the 8 resize handles plus the body itself.
    enum Handle: Sendable {
        case body
        case topLeft, top, topRight
        case left, right
        case bottomLeft, bottom, bottomRight
    }

    /// Default snap grid (5% of slide width/height — matches the prototype's
    /// dotted backdrop and lines up nicely with thirds and quarters).
    static let defaultGridStep: Double = 0.05

    /// Tolerance for snapping to an alignment candidate (slide center, another
    /// element's edges/center). 1.2% of slide width — tight enough to feel
    /// intentional, loose enough to feel "magnetic" while dragging.
    static let alignmentTolerance: Double = 0.012

    // MARK: - Clamping

    /// Keeps a frame inside 0…1 by shrinking + nudging. Width/height get a
    /// minimum so a drag can't accidentally collapse an element to invisibility.
    static func clamped(_ frame: Frame, minSize: Double = 0.05) -> Frame {
        var width = max(minSize, min(1.0, frame.width))
        var height = max(minSize, min(1.0, frame.height))
        var x = min(max(0, frame.x), 1.0 - width)
        var y = min(max(0, frame.y), 1.0 - height)
        if width > 1 { width = 1; x = 0 }
        if height > 1 { height = 1; y = 0 }
        return Frame(x: x, y: y, width: width, height: height)
    }

    // MARK: - Snapping (grid)

    /// Snaps a scalar to the nearest grid multiple. Off → returns the input.
    static func snapped(_ value: Double, step: Double = defaultGridStep, enabled: Bool) -> Double {
        guard enabled, step > 0 else { return value }
        return (value / step).rounded() * step
    }

    /// Snaps a frame's top-left + size to the grid (8 handles' worth of
    /// candidate edges). Use after a drag/resize to coast the result onto the
    /// grid; bail out by passing `enabled: false`.
    static func snappedToGrid(_ frame: Frame, step: Double = defaultGridStep,
                              enabled: Bool) -> Frame {
        guard enabled else { return frame }
        let x = snapped(frame.x, step: step, enabled: true)
        let y = snapped(frame.y, step: step, enabled: true)
        let w = snapped(frame.width, step: step, enabled: true)
        let h = snapped(frame.height, step: step, enabled: true)
        return Frame(x: x, y: y, width: max(step, w), height: max(step, h))
    }

    // MARK: - Alignment guides

    /// Candidate vertical lines (x positions) and horizontal lines (y positions)
    /// the dragged element should "feel" while moving — slide center (`0.5`),
    /// slide edges (`0`, `1`), and every other element's left/centerX/right
    /// (or top/centerY/bottom). The editor renders the matched lines as guides.
    struct AlignmentCandidates: Equatable, Sendable {
        var verticals: [Double]
        var horizontals: [Double]
    }

    static func alignmentCandidates(against others: [Frame]) -> AlignmentCandidates {
        var verticals: [Double] = [0, 0.5, 1]
        var horizontals: [Double] = [0, 0.5, 1]
        for frame in others {
            verticals.append(contentsOf: [frame.minX, frame.centerX, frame.maxX])
            horizontals.append(contentsOf: [frame.minY, frame.centerY, frame.maxY])
        }
        return AlignmentCandidates(
            verticals: verticals.uniqued().sorted(),
            horizontals: horizontals.uniqued().sorted())
    }

    /// Returns the candidate `verticals` line that's within `tolerance` of any
    /// of the dragged frame's interesting x positions (left, centerX, right),
    /// along with which of those positions matched. Nil = no snap.
    static func snapVertical(frame: Frame,
                             candidates: AlignmentCandidates,
                             tolerance: Double = alignmentTolerance) -> (line: Double, anchor: SnapAnchor)? {
        let anchors: [(Double, SnapAnchor)] = [
            (frame.minX, .leading),
            (frame.centerX, .center),
            (frame.maxX, .trailing),
        ]
        return nearest(in: candidates.verticals, anchors: anchors, tolerance: tolerance)
    }

    /// Like ``snapVertical`` but for horizontal lines + the frame's y anchors.
    static func snapHorizontal(frame: Frame,
                               candidates: AlignmentCandidates,
                               tolerance: Double = alignmentTolerance) -> (line: Double, anchor: SnapAnchor)? {
        let anchors: [(Double, SnapAnchor)] = [
            (frame.minY, .leading),
            (frame.centerY, .center),
            (frame.maxY, .trailing),
        ]
        return nearest(in: candidates.horizontals, anchors: anchors, tolerance: tolerance)
    }

    enum SnapAnchor: Sendable { case leading, center, trailing }

    // MARK: - Drag + resize

    /// Returns the frame produced by dragging `start` by `dx`/`dy` (in 0…1
    /// units) from `handle`. Body drags move the whole frame; handle drags
    /// resize one or two edges.
    static func dragged(_ start: Frame, by dx: Double, dy: Double, handle: Handle) -> Frame {
        switch handle {
        case .body:
            return Frame(x: start.x + dx, y: start.y + dy,
                         width: start.width, height: start.height)
        case .topLeft:
            return Frame(x: start.x + dx, y: start.y + dy,
                         width: start.width - dx, height: start.height - dy)
        case .top:
            return Frame(x: start.x, y: start.y + dy,
                         width: start.width, height: start.height - dy)
        case .topRight:
            return Frame(x: start.x, y: start.y + dy,
                         width: start.width + dx, height: start.height - dy)
        case .left:
            return Frame(x: start.x + dx, y: start.y,
                         width: start.width - dx, height: start.height)
        case .right:
            return Frame(x: start.x, y: start.y,
                         width: start.width + dx, height: start.height)
        case .bottomLeft:
            return Frame(x: start.x + dx, y: start.y,
                         width: start.width - dx, height: start.height + dy)
        case .bottom:
            return Frame(x: start.x, y: start.y,
                         width: start.width, height: start.height + dy)
        case .bottomRight:
            return Frame(x: start.x, y: start.y,
                         width: start.width + dx, height: start.height + dy)
        }
    }

    // MARK: - Layer order

    /// Returns the orders for `items` after raising `id`'s entry one slot
    /// (no-op if it's already on top).
    static func raised(_ id: Int, in items: [Int]) -> [Int] {
        guard let index = items.firstIndex(of: id), index < items.count - 1 else { return items }
        var result = items
        result.swapAt(index, index + 1)
        return result
    }

    /// Mirrors `raised` for the lower direction.
    static func lowered(_ id: Int, in items: [Int]) -> [Int] {
        guard let index = items.firstIndex(of: id), index > 0 else { return items }
        var result = items
        result.swapAt(index, index - 1)
        return result
    }

    /// Pulls `id` to the front (last) of the order. No-op if it isn't present.
    static func movedToFront(_ id: Int, in items: [Int]) -> [Int] {
        guard let index = items.firstIndex(of: id) else { return items }
        var result = items
        let value = result.remove(at: index)
        result.append(value)
        return result
    }

    /// Pushes `id` to the back (first slot) of the order. No-op if absent.
    static func movedToBack(_ id: Int, in items: [Int]) -> [Int] {
        guard let index = items.firstIndex(of: id) else { return items }
        var result = items
        let value = result.remove(at: index)
        result.insert(value, at: 0)
        return result
    }

    // MARK: - Private

    private static func nearest(in candidates: [Double],
                                anchors: [(Double, SnapAnchor)],
                                tolerance: Double) -> (line: Double, anchor: SnapAnchor)? {
        var best: (Double, SnapAnchor, Double)? = nil
        for candidate in candidates {
            for (value, anchor) in anchors {
                let delta = abs(candidate - value)
                if delta <= tolerance, best == nil || delta < best!.2 {
                    best = (candidate, anchor, delta)
                }
            }
        }
        return best.map { ($0.0, $0.1) }
    }
}

private extension Array where Element: Hashable {
    /// Deduplicates while preserving the first occurrence's order.
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
