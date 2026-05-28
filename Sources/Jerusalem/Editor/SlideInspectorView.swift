import SwiftUI
import SwiftData

/// Phase 8 inspector. Edits the selected element's typography + effects + the
/// slide's background. Each mutation flips ``Slide/isManuallyEdited`` so the
/// rebuilder steps back and leaves the editor's work alone.
struct SlideInspectorView: View {
    @Bindable var item: Item
    @Bindable var slide: Slide
    /// The currently selected element, or `nil` if only the slide is "selected".
    /// Lookup is done by the parent so the inspector doesn't fight selection state.
    var selectedElement: SlideElement?

    var body: some View {
        Form {
            slideSection
            if let element = selectedElement {
                ElementInspector(element: element, onChange: markEdited)
                SlideArrangeSection(slide: slide, element: element, onChange: markEdited)
            } else {
                Section {
                    Text("Tap an element on the canvas to edit it.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            SlideThemeSection(item: item, selectedElement: selectedElement, onChange: markEdited)
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var slideSection: some View {
        Section {
            TextField("Section label", text: Binding(
                get: { slide.sectionLabel ?? "" },
                set: { slide.sectionLabel = $0.isEmpty ? nil : $0 }))
        } header: { Text("Slide") }

        SlideBackgroundSection(slide: slide, onChange: markEdited)
    }

    private func markEdited() { slide.isManuallyEdited = true }
}

/// Element-specific section. Extracted so the parent's `body` stays narrow
/// enough for SwiftUI's type-checker.
private struct ElementInspector: View {
    @Bindable var element: SlideElement
    var onChange: () -> Void

    private static let fontChoices = ["Avenir Next", "SF Pro Text", "Helvetica Neue",
                                      "Georgia", "Times New Roman", "Menlo"]

    var body: some View {
        Section {
            if element.kind == .text {
                TextField("Text", text: Binding(
                    get: { element.text ?? "" },
                    set: { element.text = $0; onChange() }),
                          axis: .vertical)
                    .lineLimit(2...6)
            }
        } header: { Text("Content") }

        if element.kind == .text {
            fontSection
            paragraphSection
            strokeAndShadowSection
        }
    }

    // MARK: - Font (family · size · color · B/I/U)

    @ViewBuilder private var fontSection: some View {
        Section {
            Picker("Family", selection: $element.fontName) {
                ForEach(Self.fontChoices, id: \.self) { Text($0).tag($0) }
            }
            HStack {
                Stepper(value: $element.fontSize, in: 12...240, step: 2) {
                    LabeledContent("Size", value: "\(Int(element.fontSize)) pt")
                }
                ColorPicker("", selection: Binding(
                    get: { Color(hex: element.colorHex) },
                    set: { element.colorHex = $0.hexString; onChange() }))
                    .labelsHidden()
            }
            HStack {
                Toggle("B", isOn: $element.isBold).toggleStyle(.button)
                    .font(.body.bold())
                Toggle("I", isOn: $element.isItalic).toggleStyle(.button)
                    .font(.body.italic())
                Toggle("U", isOn: $element.isUnderlined).toggleStyle(.button)
                    .underline(element.isUnderlined)
                Spacer()
            }
        } header: { Text("Font") }
    }

    // MARK: - Paragraph (alignment · line/letter spacing · autofit)

    @ViewBuilder private var paragraphSection: some View {
        Section {
            Picker("Alignment", selection: $element.alignment) {
                Image(systemName: "text.alignleft").tag(TextAlignmentOption.leading)
                Image(systemName: "text.aligncenter").tag(TextAlignmentOption.center)
                Image(systemName: "text.alignright").tag(TextAlignmentOption.trailing)
                Image(systemName: "text.justify").tag(TextAlignmentOption.justified)
            }
            .pickerStyle(.segmented)
            VStack(alignment: .leading) {
                LabeledContent("Line spacing", value: String(format: "%.2f×", element.lineSpacingMultiplier))
                Slider(value: $element.lineSpacingMultiplier, in: 0.9...2.2, step: 0.05) { _ in onChange() }
            }
            VStack(alignment: .leading) {
                LabeledContent("Letter spacing", value: String(format: "%.1f", element.letterSpacing))
                Slider(value: $element.letterSpacing, in: -3...12, step: 0.5) { _ in onChange() }
            }
            Toggle("Auto-fit", isOn: $element.autoFit)
        } header: { Text("Paragraph") }
    }

    // MARK: - Stroke & Shadow

    @ViewBuilder private var strokeAndShadowSection: some View {
        Section {
            HStack {
                Toggle("Outline", isOn: $element.hasStroke)
                Spacer()
                ColorPicker("", selection: Binding(
                    get: { Color(hex: element.strokeColorHex) },
                    set: { element.strokeColorHex = $0.hexString; onChange() }))
                    .labelsHidden()
                    .disabled(!element.hasStroke)
            }
            VStack(alignment: .leading) {
                LabeledContent("Outline width", value: String(format: "%.1f", element.strokeWidth))
                Slider(value: $element.strokeWidth, in: 0...10, step: 0.5) { _ in onChange() }
                    .disabled(!element.hasStroke)
            }
            HStack {
                Toggle("Shadow", isOn: $element.hasShadow)
                Spacer()
                ColorPicker("", selection: Binding(
                    get: { Color(hex: element.shadowColorHex) },
                    set: { element.shadowColorHex = $0.hexString; onChange() }))
                    .labelsHidden()
                    .disabled(!element.hasShadow)
            }
            VStack(alignment: .leading) {
                LabeledContent("Shadow blur", value: String(format: "%.0f", element.shadowBlur))
                Slider(value: $element.shadowBlur, in: 0...40, step: 1) { _ in onChange() }
                    .disabled(!element.hasShadow)
            }
            VStack(alignment: .leading) {
                LabeledContent("Shadow offset", value: String(format: "%.0f", element.shadowOffsetY))
                Slider(value: $element.shadowOffsetY, in: -20...20, step: 1) { _ in onChange() }
                    .disabled(!element.hasShadow)
            }
        } header: { Text("Stroke & Shadow") }
    }

}
