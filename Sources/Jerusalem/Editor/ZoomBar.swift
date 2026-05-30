import SwiftUI

/// Shared zoom bounds + math for the editor canvas. The ZoomBar buttons,
/// trackpad pinch, and ⌘-scroll all funnel through this so they agree.
enum CanvasZoomMath {
    static let range: ClosedRange<CGFloat> = 0.5...2.0

    static func clamp(_ value: CGFloat) -> CGFloat {
        min(range.upperBound, max(range.lowerBound, value))
    }
    /// Pinch: `magnification` is the incremental factor of one magnify event.
    static func applying(magnify magnification: CGFloat, to zoom: CGFloat) -> CGFloat {
        clamp(zoom * (1 + magnification))
    }
    /// ⌘-scroll: `delta` is the already-scaled additive zoom change.
    static func applying(scroll delta: CGFloat, to zoom: CGFloat) -> CGFloat {
        clamp(zoom + delta)
    }
}

/// The stage's bottom-left zoom control (Phase 8.4) — mirrors the prototype's
/// `.zoombar`. A `− NN% +` capsule that steps the editor zoom between 50% and
/// 200%. Trackpad pinch and ⌘-scroll zoom the same `zoom` state. Native buttons +
/// a material capsule rather than the prototype's bespoke chrome.
struct ZoomBar: View {
    @Binding var zoom: CGFloat

    private let range = CanvasZoomMath.range
    private let step: CGFloat = 0.1

    var body: some View {
        HStack(spacing: 8) {
            Button { set(zoom - step) } label: { Image(systemName: "minus") }
                .disabled(zoom <= range.lowerBound + 0.001)
            Text("\(Int((zoom * 100).rounded()))%")
                .font(.callout.monospacedDigit())
                .frame(width: 42)
            Button { set(zoom + step) } label: { Image(systemName: "plus") }
                .disabled(zoom >= range.upperBound - 0.001)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
    }

    private func set(_ value: CGFloat) {
        zoom = CanvasZoomMath.clamp(value)
    }
}
