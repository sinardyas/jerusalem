import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

/// Inspector "Background (slide)" section from Phase 8.3.2. Lets the operator
/// pick between the four background kinds (color, gradient, image, video),
/// surfaces a curated swatch palette + a "More…" picker, and gates the
/// gradient angle / second color and image / video pickers on the selected
/// kind so the form never displays controls the renderer would ignore.
struct SlideBackgroundSection: View {
    @Bindable var slide: Slide
    var onChange: () -> Void

    /// Curated palette for the swatch grid. The "More…" picker can author any
    /// hex; this set is just the prototype's quick-picks.
    private static let palette: [String] = [
        "#0F172A", // dark navy (default)
        "#1E3A8A", // royal blue
        "#5B21B6", // violet
        "#7C2D12", // burnt sienna
    ]

    var body: some View {
        Section {
            Picker("Type", selection: Binding(
                get: { slide.backgroundKind },
                set: { slide.backgroundKind = $0; onChange() })) {
                Text("Color").tag(SlideBackgroundKind.color)
                Text("Gradient").tag(SlideBackgroundKind.gradient)
                Text("Image").tag(SlideBackgroundKind.image)
                Text("Video").tag(SlideBackgroundKind.video)
            }
            .pickerStyle(.segmented)

            switch slide.backgroundKind {
            case .color:    colorControls
            case .gradient: gradientControls
            case .image:    imageControls
            case .video:    videoControls
            }
        } header: { Text("Background") }
    }

    // MARK: - Color

    @ViewBuilder private var colorControls: some View {
        SwatchGrid(palette: Self.palette,
                   selected: slide.backgroundColorHex,
                   onSelect: { hex in slide.backgroundColorHex = hex; onChange() })
        ColorPicker("More…", selection: Binding(
            get: { Color(hex: slide.backgroundColorHex) },
            set: { slide.backgroundColorHex = $0.hexString; onChange() }))
    }

    // MARK: - Gradient

    @ViewBuilder private var gradientControls: some View {
        ColorPicker("First color", selection: Binding(
            get: { Color(hex: slide.backgroundColorHex) },
            set: { slide.backgroundColorHex = $0.hexString; onChange() }))
        ColorPicker("Second color", selection: Binding(
            get: { Color(hex: slide.gradientHex2 ?? "#1E3A8A") },
            set: { slide.gradientHex2 = $0.hexString; onChange() }))
        Stepper(value: Binding(
            get: { Int(slide.gradientAngle.rounded()) },
            set: { slide.gradientAngle = Double($0); onChange() }),
                in: 0...359, step: 15) {
            LabeledContent("Angle", value: "\(Int(slide.gradientAngle.rounded()))°")
        }
    }

    // MARK: - Image

    @ViewBuilder private var imageControls: some View {
        if let filename = slide.backgroundImageFilename {
            LabeledContent("File") {
                Text(filename).lineLimit(1).truncationMode(.middle)
                    .foregroundStyle(.secondary)
            }
        }
        HStack {
            Button("Choose image…") { pickImage() }
            if slide.backgroundImageFilename != nil {
                Spacer()
                Button("Remove", role: .destructive) {
                    slide.backgroundImageFilename = nil
                    onChange()
                }
            }
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
            let filename = try MediaStorage.importFile(at: url)
            slide.backgroundImageFilename = filename
            onChange()
        } catch {
            NSSound.beep()
        }
    }

    // MARK: - Video

    @ViewBuilder private var videoControls: some View {
        if let filename = slide.backgroundVideoFilename {
            LabeledContent("File") {
                Text(filename).lineLimit(1).truncationMode(.middle)
                    .foregroundStyle(.secondary)
            }
        }
        HStack {
            Button("Choose video…") { pickVideo() }
            if slide.backgroundVideoFilename != nil {
                Spacer()
                Button("Remove", role: .destructive) {
                    slide.backgroundVideoFilename = nil
                    onChange()
                }
            }
        }
    }

    private func pickVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let filename = try MediaStorage.importFile(at: url)
            slide.backgroundVideoFilename = filename
            onChange()
        } catch {
            NSSound.beep()
        }
    }
}

/// Color swatch grid used by ``SlideBackgroundSection`` (and reusable by the
/// theme picker in Phase 8.3.3).
struct SwatchGrid: View {
    let palette: [String]
    let selected: String
    let onSelect: (String) -> Void

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(palette, id: \.self) { hex in
                Button(action: { onSelect(hex) }) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(hex: hex))
                        .frame(height: 28)
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(hex == selected ? Color.accentColor : Color.gray.opacity(0.3),
                                          lineWidth: hex == selected ? 2 : 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
