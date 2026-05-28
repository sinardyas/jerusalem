import SwiftUI
import SwiftData

/// Inspector "Arrange" section from Phase 8.3.3. Replaces the legacy 4-Stepper
/// Position section with a 2×2 percent grid + a Front/Forward/Back/Send-to-Back
/// button row. Edits clamp through ``SlideGeometry.clamped`` and reorder via
/// the four order helpers; touching either flips ``Slide.isManuallyEdited``.
struct SlideArrangeSection: View {
    @Bindable var slide: Slide
    @Bindable var element: SlideElement
    var onChange: () -> Void

    var body: some View {
        Section {
            HStack(spacing: 8) {
                percentField("X", value: bindingFor(\.x, min: 0))
                percentField("Y", value: bindingFor(\.y, min: 0))
            }
            HStack(spacing: 8) {
                percentField("W", value: bindingFor(\.width, min: SlideGeometry.defaultGridStep))
                percentField("H", value: bindingFor(\.height, min: SlideGeometry.defaultGridStep))
            }
            HStack(spacing: 6) {
                Button { reorder(.front) } label: {
                    Image(systemName: "square.3.layers.3d.top.filled")
                }.help("Bring to Front")
                Button { reorder(.forward) } label: {
                    Image(systemName: "square.2.layers.3d.top.filled")
                }.help("Bring Forward")
                Button { reorder(.backward) } label: {
                    Image(systemName: "square.2.layers.3d.bottom.filled")
                }.help("Send Backward")
                Button { reorder(.back) } label: {
                    Image(systemName: "square.3.layers.3d.bottom.filled")
                }.help("Send to Back")
            }
            .buttonStyle(.bordered)
        } header: { Text("Arrange") }
    }

    // MARK: - Percent field

    private func percentField(_ label: String, value: Binding<Double>) -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(.secondary).frame(width: 14, alignment: .leading)
            TextField("", text: percentText(value))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 80)
        }
    }

    private func percentText(_ binding: Binding<Double>) -> Binding<String> {
        Binding(
            get: { String(format: "%.1f%%", binding.wrappedValue * 100) },
            set: { newValue in
                let stripped = newValue.trimmingCharacters(in: CharacterSet(charactersIn: "%, "))
                guard let parsed = Double(stripped) else { return }
                binding.wrappedValue = parsed / 100.0
            })
    }

    // MARK: - Geometry binding

    private func bindingFor(_ keyPath: WritableKeyPath<SlideGeometry.Frame, Double>,
                            min: Double) -> Binding<Double> {
        Binding(
            get: { currentFrame[keyPath: keyPath] },
            set: { newValue in
                var f = currentFrame
                f[keyPath: keyPath] = newValue
                let clamped = SlideGeometry.clamped(f, minSize: min)
                element.x = clamped.x
                element.y = clamped.y
                element.width = clamped.width
                element.height = clamped.height
                onChange()
            })
    }

    private var currentFrame: SlideGeometry.Frame {
        SlideGeometry.Frame(x: element.x, y: element.y,
                            width: element.width, height: element.height)
    }

    // MARK: - Reorder

    private enum Movement { case front, forward, backward, back }

    private func reorder(_ movement: Movement) {
        let ordered = slide.orderedElements
        // Use the *current* index as a stable identity for the move calculation;
        // the helpers shuffle those indices and we then rewrite each element's
        // `order` from the resulting position, which sidesteps any duplicate-
        // order edge case.
        let indices = Array(ordered.indices)
        guard let currentIndex = ordered.firstIndex(where: {
            $0.persistentModelID == element.persistentModelID
        }) else { return }
        let newIndices: [Int]
        switch movement {
        case .front:    newIndices = SlideGeometry.movedToFront(currentIndex, in: indices)
        case .back:     newIndices = SlideGeometry.movedToBack(currentIndex, in: indices)
        case .forward:  newIndices = SlideGeometry.raised(currentIndex, in: indices)
        case .backward: newIndices = SlideGeometry.lowered(currentIndex, in: indices)
        }
        for (position, oldIndex) in newIndices.enumerated() {
            ordered[oldIndex].order = position
        }
        onChange()
    }
}
