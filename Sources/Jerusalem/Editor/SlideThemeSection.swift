import SwiftUI
import SwiftData

/// Inspector "Theme" section from Phase 8.3.3. Shows a tiny preview swatch,
/// the theme's name, a Change… stub (only the bundled "Default Dark" exists in
/// MVP — full theme library is a Phase-2 feature), and the primary
/// "Set as default style for new slides" link that pushes the selected text
/// element's typography back into `item.theme`.
struct SlideThemeSection: View {
    @Bindable var item: Item
    /// May be nil if no element is selected — the Set-as-default link disables
    /// in that case but the preview swatch still renders.
    var selectedElement: SlideElement?
    var onChange: () -> Void

    @State private var showThemePicker = false

    private var theme: Theme {
        if let existing = item.theme { return existing }
        let fresh = Theme.makeDefault()
        item.theme = fresh
        return fresh
    }

    var body: some View {
        InspectorSection(title: "Theme") {
            HStack(alignment: .center, spacing: 10) {
                ThemePreviewSwatch(theme: theme)
                    .frame(width: 80, height: 45)
                VStack(alignment: .leading, spacing: 2) {
                    Text(theme.name).font(.callout)
                    Button("Change…") { showThemePicker = true }
                        .buttonStyle(.link)
                }
                Spacer()
            }
            Button {
                guard let element = selectedElement, element.kind == .text else { return }
                theme.copy(from: element)
                onChange()
            } label: {
                Label("Set as default style for new slides", systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .disabled(selectedElement?.kind != .text)
        }
        .sheet(isPresented: $showThemePicker) {
            ThemePickerSheet(currentTheme: theme,
                             onPick: { _ in showThemePicker = false })
        }
    }
}

/// Tiny preview of a theme's headline typography on its background — used in
/// the inspector and the picker sheet.
struct ThemePreviewSwatch: View {
    let theme: Theme

    var body: some View {
        ZStack {
            Color(hex: theme.backgroundColorHex)
            Text("Aa")
                .font(.custom(theme.fontName, size: 20).weight(theme.isBold ? .bold : .regular))
                .foregroundStyle(Color(hex: theme.textColorHex))
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4)
            .strokeBorder(Color.gray.opacity(0.3), lineWidth: 1))
    }
}

/// Bundled-themes picker. Only ships the one default for the MVP — a real
/// theme library is a Phase-2 concept per docs/MVP.md §6, so this sheet
/// renders a single row and a future-hook for more themes.
struct ThemePickerSheet: View {
    let currentTheme: Theme
    var onPick: (Theme) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose Theme").font(.title3.bold())
            HStack(spacing: 10) {
                ThemePreviewSwatch(theme: currentTheme)
                    .frame(width: 80, height: 45)
                VStack(alignment: .leading, spacing: 2) {
                    Text(currentTheme.name).font(.callout)
                    Text("Bundled default").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            .padding(8)
            .background(Color.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))

            Text("More themes ship in a future update.")
                .font(.caption).foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 320, minHeight: 200)
    }
}
