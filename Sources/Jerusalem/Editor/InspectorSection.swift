import SwiftUI

/// A titled section in the re-skinned inspector (Phase 8.4). Replaces the
/// System-Settings `.formStyle(.grouped)` card with the prototype's denser
/// `.sec` block: an uppercase, dimmed, letter-spaced header over content, with a
/// hairline divider beneath. Hosted inside a plain `ScrollView { VStack }`.
struct InspectorSection<Content: View>: View {
    let title: String
    /// Optional dimmed, non-uppercase suffix — e.g. the prototype's "(slide)".
    var trailing: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(.secondary)
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        Divider()
    }
}

/// A label-left / control-right row matching the prototype's `.ctl`. The control
/// is right-aligned and may expand (e.g. a full-width menu picker or a slider).
struct InspectorRow<Control: View>: View {
    let label: String
    var labelWidth: CGFloat = 64
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.callout)
                .frame(width: labelWidth, alignment: .leading)
            control
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

/// The inspector's top header chip (prototype `.hd`): a colored glyph tile plus
/// the selected object's type name ("Text Box" / "Image" / "Shape" / "Slide").
struct InspectorHeaderChip: View {
    /// The selected element's kind, or `nil` when only the slide is in focus.
    let kind: SlideElementKind?

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 5)
                .fill(descriptor.color)
                .frame(width: 20, height: 20)
                .overlay(Image(systemName: descriptor.glyph)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white))
            Text(descriptor.title)
                .font(.headline)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private var descriptor: (glyph: String, color: Color, title: String) {
        switch kind {
        case .text:  return ("textformat", .orange, "Text Box")
        case .image: return ("photo", .blue, "Image")
        case .shape: return ("square.on.circle", .purple, "Shape")
        case nil:    return ("rectangle.on.rectangle", .gray, "Slide")
        }
    }
}
