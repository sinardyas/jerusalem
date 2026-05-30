import SwiftUI
import SwiftData

/// Phase 6 song editor: type lyrics with `[Verse 1]` / `[Chorus]` markers, set
/// lines-per-slide, and see the slide grid regenerate. The lyrics block is the
/// canonical authored source; ``ContentRebuilder`` materializes the slides the
/// Phase 2 renderer + Phase 4 navigation already consume.
struct SongEditorView: View {
    @Bindable var item: Item
    @Environment(LiveState.self) private var live

    @State private var lyrics: String = ""
    @State private var rebuildTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section("Song") {
                TextField("Title", text: $item.title)
                TextField("Author (subtitle)", text: Binding(
                    get: { item.subtitle ?? "" },
                    set: { item.subtitle = $0.isEmpty ? nil : $0 }))
                Stepper(value: $item.linesPerSlide, in: 1...8) {
                    LabeledContent("Lines per slide", value: "\(item.linesPerSlide)")
                }
                .onChange(of: item.linesPerSlide) { _, _ in
                    ContentRebuilder.rebuild(item)
                    rearmIfShowing()
                }
            }

            Section {
                TextEditor(text: $lyrics)
                    .font(.body.monospaced())
                    .frame(minHeight: 140)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
                    .onChange(of: lyrics) { _, newValue in
                        scheduleRebuild(newValue)
                    }
            } header: {
                Text("Lyrics")
            } footer: {
                Text("""
                Wrap each section header in brackets on its own line:
                `[Verse 1]`, `[Chorus]`, `[Bridge]`, `[Tag]`.
                Slides regenerate as you type.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Derived slides") {
                LabeledContent("Slides", value: "\(item.orderedSlides.count)")
                LabeledContent("Sections", value: "\(item.orderedSongSections.count)")
                if ContentRebuilder.hasManualEdits(item) {
                    Button(role: .destructive) {
                        ContentRebuilder.resetToAutoDerived(item)
                        rearmIfShowing()
                    } label: {
                        Label("Restore auto-generated slides", systemImage: "arrow.uturn.backward")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { lyrics = ContentRebuilder.lyricsText(for: item) }
        .onChange(of: item.persistentModelID) { _, _ in
            lyrics = ContentRebuilder.lyricsText(for: item)
        }
        .onDisappear {
            rebuildTask?.cancel()
            // Flush a pending edit so we don't lose the last keystrokes.
            ContentRebuilder.setLyrics(lyrics, on: item)
        }
    }

    /// Debounces rebuilds so we're not thrashing SwiftData on every keystroke.
    private func scheduleRebuild(_ text: String) {
        rebuildTask?.cancel()
        rebuildTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            ContentRebuilder.setLyrics(text, on: item)
            rearmIfShowing()
        }
    }

    /// If the editor's item is what LiveState is currently programmed with,
    /// re-arm so the slide grid + Next preview reflect the new slides immediately.
    private func rearmIfShowing() {
        live.arm(LiveState.programSlides(for: item))
    }
}
