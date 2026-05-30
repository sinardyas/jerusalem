import SwiftUI
import SwiftData

/// Phase 6 editor for sermon/text items: a title slide plus body paragraphs that
/// become bullet/point slides via ``SlideSplitter``. Paragraphs are separated by
/// blank lines; long paragraphs are further split by `linesPerSlide`.
struct SermonEditorView: View {
    @Bindable var item: Item
    @Environment(LiveState.self) private var live

    @State private var bodyDraft: String = ""
    @State private var rebuildTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section("Item") {
                TextField("Title", text: $item.title)
                    .onChange(of: item.title) { _, _ in
                        ContentRebuilder.rebuild(item)
                        rearm()
                    }
                TextField("Subtitle", text: Binding(
                    get: { item.subtitle ?? "" },
                    set: { item.subtitle = $0.isEmpty ? nil : $0 }))
                Stepper(value: $item.linesPerSlide, in: 1...8) {
                    LabeledContent("Lines per slide", value: "\(item.linesPerSlide)")
                }
                .onChange(of: item.linesPerSlide) { _, _ in
                    ContentRebuilder.rebuild(item)
                    rearm()
                }
            }

            Section {
                TextEditor(text: $bodyDraft)
                    .font(.body)
                    .frame(minHeight: 140)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
                    .onChange(of: bodyDraft) { _, newValue in
                        scheduleRebuild(newValue)
                    }
            } header: {
                Text("Body")
            } footer: {
                Text("Separate points with a blank line. Each point becomes its own slide.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Derived slides") {
                LabeledContent("Slides", value: "\(item.orderedSlides.count)")
                if ContentRebuilder.hasManualEdits(item) {
                    Button(role: .destructive) {
                        ContentRebuilder.resetToAutoDerived(item)
                        rearm()
                    } label: {
                        Label("Restore auto-generated slides", systemImage: "arrow.uturn.backward")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { bodyDraft = item.bodyText ?? "" }
        .onChange(of: item.persistentModelID) { _, _ in bodyDraft = item.bodyText ?? "" }
        .onDisappear {
            rebuildTask?.cancel()
            ContentRebuilder.setBody(bodyDraft, on: item)
        }
    }

    private func scheduleRebuild(_ text: String) {
        rebuildTask?.cancel()
        rebuildTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            ContentRebuilder.setBody(text, on: item)
            rearm()
        }
    }

    private func rearm() {
        live.arm(LiveState.programSlides(for: item))
    }
}
