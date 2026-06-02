import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

/// Phase 8 inspector, re-skinned in Phase 8.4 to the prototype's dense panel of
/// titled ``InspectorSection`` blocks built from native macOS controls. Phase
/// 8.11 split the single scrolling column into three tabs (``InspectorTab``) so
/// per-object concerns no longer interleave with slide-wide ones:
/// **Format** (the selected element's styling — Font/Paragraph/Stroke & Shadow,
/// or Shape, or Image), **Arrange** (position/size + layer order), and
/// **Slide** (label, background, theme). Selecting an object auto-focuses
/// Format; deselecting returns to Slide. Each mutation flips
/// ``Slide/isManuallyEdited`` so the rebuilder steps back and leaves the
/// editor's work alone.
struct SlideInspectorView: View {
    @Bindable var item: Item
    @Bindable var slide: Slide
    /// The currently selected element, or `nil` if only the slide is "selected".
    var selectedElement: SlideElement?

    /// Which inspector tab is showing. Defaults to `slide` (nothing selected);
    /// auto-switches on selection change via ``InspectorTab/onSelectionChange``.
    @State private var tab: InspectorTab = .slide

    var body: some View {
        VStack(spacing: 0) {
            InspectorHeaderChip(kind: selectedElement?.kind)
            Picker("", selection: $tab) {
                ForEach(InspectorTab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch tab {
                    case .format:  formatTab
                    case .arrange: arrangeTab
                    case .slide:   slideTab
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .onChange(of: selectedElement?.persistentModelID) { _, id in
            tab = InspectorTab.onSelectionChange(hasSelection: id != nil)
        }
    }

    // MARK: - Tabs

    /// The selected object's styling — or a hint to select one.
    @ViewBuilder private var formatTab: some View {
        if let element = selectedElement {
            switch element.kind {
            case .text:  TextElementInspector(element: element, onChange: markEdited)
            case .shape: ShapeElementInspector(element: element, onChange: markEdited)
            case .image: ImageElementInspector(element: element, onChange: markEdited)
            }
        } else {
            InspectorSection(title: "Format") {
                Text("Select an object on the canvas to edit its style.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The selected object's position, size, and layer order.
    @ViewBuilder private var arrangeTab: some View {
        if let element = selectedElement {
            SlideArrangeSection(slide: slide, element: element, onChange: markEdited)
        } else {
            InspectorSection(title: "Arrange") {
                Text("Select an object on the canvas to position it.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Slide-wide settings: label, background, and theme.
    @ViewBuilder private var slideTab: some View {
        slideSection
        SlideBackgroundSection(slide: slide, onChange: markEdited)
        SlideThemeSection(item: item, selectedElement: selectedElement, onChange: markEdited)
    }

    private var slideSection: some View {
        InspectorSection(title: "Slide") {
            InspectorRow(label: "Label") {
                TextField("Section label", text: Binding(
                    get: { slide.sectionLabel ?? "" },
                    set: { slide.sectionLabel = $0.isEmpty ? nil : $0 }))
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private func markEdited() { slide.isManuallyEdited = true }
}

// MARK: - Text element (Font · Paragraph · Stroke & Shadow)

private struct TextElementInspector: View {
    @Bindable var element: SlideElement
    var onChange: () -> Void

    private static let fontChoices = ["Avenir Next", "SF Pro Text", "Helvetica Neue",
                                      "Georgia", "Times New Roman", "Menlo"]

    var body: some View {
        fontSection
        paragraphSection
        strokeShadowSection
    }

    private var fontSection: some View {
        InspectorSection(title: "Font") {
            InspectorRow(label: "Family") {
                Picker("", selection: edited(\.fontName)) {
                    ForEach(Self.fontChoices, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
            }
            InspectorRow(label: "Size") {
                HStack(spacing: 8) {
                    TextField("", value: fontSizeBinding, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                        .multilineTextAlignment(.trailing)
                    Stepper("", value: fontSizeBinding, in: 8...400, step: 1)
                        .labelsHidden()
                    ColorPicker("", selection: colorBinding(\.colorHex)).labelsHidden()
                }
            }
            InspectorRow(label: "Style") {
                HStack(spacing: 6) {
                    Toggle("B", isOn: edited(\.isBold)).font(.body.bold())
                    Toggle("I", isOn: edited(\.isItalic)).font(.body.italic())
                    Toggle("U", isOn: edited(\.isUnderlined)).underline(element.isUnderlined)
                }
                .toggleStyle(.button)
            }
        }
    }

    private var paragraphSection: some View {
        InspectorSection(title: "Paragraph") {
            Picker("", selection: edited(\.alignment)) {
                Image(systemName: "text.alignleft").tag(TextAlignmentOption.leading)
                Image(systemName: "text.aligncenter").tag(TextAlignmentOption.center)
                Image(systemName: "text.alignright").tag(TextAlignmentOption.trailing)
                Image(systemName: "text.justify").tag(TextAlignmentOption.justified)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            sliderRow("Line", value: edited(\.lineSpacingMultiplier), range: 0.9...2.2, step: 0.05,
                      display: String(format: "%.2f×", element.lineSpacingMultiplier))
            sliderRow("Letter", value: edited(\.letterSpacing), range: -3...12, step: 0.5,
                      display: String(format: "%.1f", element.letterSpacing))
            InspectorRow(label: "Auto-fit") {
                Toggle("", isOn: edited(\.autoFit)).labelsHidden().toggleStyle(.switch)
            }
        }
    }

    private var strokeShadowSection: some View {
        InspectorSection(title: "Stroke & Shadow") {
            InspectorRow(label: "Outline") {
                HStack(spacing: 8) {
                    Toggle("", isOn: edited(\.hasStroke)).labelsHidden().toggleStyle(.switch)
                    ColorPicker("", selection: colorBinding(\.strokeColorHex)).labelsHidden()
                        .disabled(!element.hasStroke)
                }
            }
            sliderRow("Width", value: edited(\.strokeWidth), range: 0...10, step: 0.5,
                      display: String(format: "%.1f", element.strokeWidth))
                .disabled(!element.hasStroke)
            InspectorRow(label: "Shadow") {
                HStack(spacing: 8) {
                    Toggle("", isOn: edited(\.hasShadow)).labelsHidden().toggleStyle(.switch)
                    ColorPicker("", selection: colorBinding(\.shadowColorHex)).labelsHidden()
                        .disabled(!element.hasShadow)
                }
            }
            sliderRow("Blur", value: edited(\.shadowBlur), range: 0...40, step: 1,
                      display: String(format: "%.0f", element.shadowBlur))
                .disabled(!element.hasShadow)
            sliderRow("Offset", value: edited(\.shadowOffsetY), range: -20...20, step: 1,
                      display: String(format: "%.0f", element.shadowOffsetY))
                .disabled(!element.hasShadow)
        }
    }

    // MARK: Row + binding helpers

    private func sliderRow(_ label: String, value: Binding<Double>,
                           range: ClosedRange<Double>, step: Double, display: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(.callout)
                Spacer()
                Text(display).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
    }

    /// Binding to a model property that fires `onChange` (marks the slide edited).
    private func edited<T>(_ keyPath: ReferenceWritableKeyPath<SlideElement, T>) -> Binding<T> {
        Binding(get: { element[keyPath: keyPath] },
                set: { element[keyPath: keyPath] = $0; onChange() })
    }
    /// Font size, clamped to a sane range so a typed value can't break layout.
    private var fontSizeBinding: Binding<Double> {
        Binding(get: { element.fontSize },
                set: { element.fontSize = min(400, max(8, $0)); onChange() })
    }
    /// Hex-string property exposed as a SwiftUI `Color`.
    private func colorBinding(_ keyPath: ReferenceWritableKeyPath<SlideElement, String>) -> Binding<Color> {
        Binding(get: { Color(hex: element[keyPath: keyPath]) },
                set: { element[keyPath: keyPath] = $0.hexString; onChange() })
    }
}

// MARK: - Shape element (Shape type · Fill · Corner · Outline)

private struct ShapeElementInspector: View {
    @Bindable var element: SlideElement
    var onChange: () -> Void

    var body: some View {
        InspectorSection(title: "Shape") {
            Picker("", selection: edited(\.shapeType)) {
                Image(systemName: "rectangle").tag(ShapeType.rectangle)
                Image(systemName: "circle").tag(ShapeType.ellipse)
                Image(systemName: "rectangle.roundedtop").tag(ShapeType.roundedRectangle)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            InspectorRow(label: "Fill") {
                ColorPicker("", selection: colorBinding(\.fillColorHex)).labelsHidden()
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Corner").font(.callout)
                    Spacer()
                    Text(String(format: "%.0f", element.cornerRadius))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Slider(value: edited(\.cornerRadius), in: 0...200, step: 1)
                    .disabled(element.shapeType != .roundedRectangle)
            }
        }
        InspectorSection(title: "Outline") {
            InspectorRow(label: "Border") {
                HStack(spacing: 8) {
                    Toggle("", isOn: edited(\.hasStroke)).labelsHidden().toggleStyle(.switch)
                    ColorPicker("", selection: colorBinding(\.strokeColorHex)).labelsHidden()
                        .disabled(!element.hasStroke)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Width").font(.callout)
                    Spacer()
                    Text(String(format: "%.1f", element.strokeWidth))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Slider(value: edited(\.strokeWidth), in: 0...20, step: 0.5)
                    .disabled(!element.hasStroke)
            }
        }
    }

    private func edited<T>(_ keyPath: ReferenceWritableKeyPath<SlideElement, T>) -> Binding<T> {
        Binding(get: { element[keyPath: keyPath] },
                set: { element[keyPath: keyPath] = $0; onChange() })
    }
    private func colorBinding(_ keyPath: ReferenceWritableKeyPath<SlideElement, String>) -> Binding<Color> {
        Binding(get: { Color(hex: element[keyPath: keyPath]) },
                set: { element[keyPath: keyPath] = $0.hexString; onChange() })
    }
}

// MARK: - Image element

private struct ImageElementInspector: View {
    @Bindable var element: SlideElement
    var onChange: () -> Void

    var body: some View {
        InspectorSection(title: "Image") {
            if let filename = element.imageFilename {
                InspectorRow(label: "File") {
                    Text(filename).lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }
            }
            Button("Replace Image…") { pickImage() }
        }
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            element.imageFilename = try MediaStorage.importFile(at: url)
            onChange()
        } catch {
            NSSound.beep()
        }
    }
}
