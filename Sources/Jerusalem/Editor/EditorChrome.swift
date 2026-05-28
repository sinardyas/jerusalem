import SwiftUI

/// Bottom status bar for the editor sheet (Phase 8.2.2). Mirrors the prototype's
/// `.statusbar` strip — autosave indicator, slide aspect, pixel size, the
/// canvas affordance toggles, and the current zoom level.
struct SlideStatusBar: View {
    let aspectLabel: String
    let pixelSize: CGSize
    @Binding var snapToGrid: Bool
    @Binding var showGuides: Bool
    @Binding var showSafeArea: Bool
    let zoom: CGFloat

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Autosaved")
            }
            divider
            Text(aspectLabel)
            divider
            Text("\(Int(pixelSize.width.rounded()))×\(Int(pixelSize.height.rounded())) px")
            divider
            Toggle(isOn: $snapToGrid) { Text("Snap to grid") }
                .toggleStyle(.checkbox)
            Toggle(isOn: $showGuides) { Text("Guides") }
                .toggleStyle(.checkbox)
            Toggle(isOn: $showSafeArea) { Text("Safe area") }
                .toggleStyle(.checkbox)
            Spacer()
            Text("Zoom \(Int((zoom * 100).rounded()))%")
                .monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(Rectangle().frame(height: 0.5).foregroundStyle(.separator),
                 alignment: .top)
    }

    private var divider: some View {
        Rectangle()
            .frame(width: 1, height: 12)
            .foregroundStyle(.separator)
    }
}

/// Top-center capsule that flashes snap feedback for ~1 second. Driven by the
/// canvas via ``EditorToastCenter`` — the canvas calls `show(_:)` from its
/// alignment-snap branches and the toast self-dismisses.
@MainActor
@Observable
final class EditorToastCenter {
    var message: String? = nil
    private var clearTask: Task<Void, Never>? = nil

    func show(_ text: String) {
        // Same message in-flight? Reset the timer rather than rebuilding it —
        // dragging slowly past the snap line shouldn't make the toast flicker.
        if message == text {
            scheduleClear()
            return
        }
        message = text
        scheduleClear()
    }

    private func scheduleClear() {
        clearTask?.cancel()
        clearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.message = nil }
        }
    }
}

/// Renders the current toast as a translucent capsule near the top of the
/// stage. Stays out of the hit-testing path so it never intercepts drags.
struct EditorToast: View {
    @Bindable var center: EditorToastCenter

    var body: some View {
        VStack {
            if let message = center.message {
                Text(message)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.7), in: Capsule())
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .padding(.top, 18)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.18), value: center.message)
    }
}

/// Soft dot pattern under the stage — matches the prototype's `.stage` desk.
struct EditorDeskBackdrop: View {
    var dotSpacing: CGFloat = 18
    var dotDiameter: CGFloat = 1.5
    var dotColor: Color = .secondary

    var body: some View {
        Canvas { context, size in
            let cols = Int((size.width / dotSpacing).rounded(.up))
            let rows = Int((size.height / dotSpacing).rounded(.up))
            for col in 0...cols {
                for row in 0...rows {
                    let origin = CGPoint(x: CGFloat(col) * dotSpacing - dotDiameter / 2,
                                         y: CGFloat(row) * dotSpacing - dotDiameter / 2)
                    let rect = CGRect(origin: origin,
                                      size: CGSize(width: dotDiameter, height: dotDiameter))
                    context.fill(Path(ellipseIn: rect),
                                 with: .color(dotColor.opacity(0.35)))
                }
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}
