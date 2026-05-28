import SwiftUI
import SwiftData

/// Phase 7 Bible editor: type a reference, pick a translation, and watch the
/// slides regenerate from the bundled scripture store. Empty/unknown references
/// clear the slide grid so the operator sees the unknown state instead of
/// stale content.
struct BibleEditorView: View {
    @Bindable var item: Item
    @Environment(LiveState.self) private var live

    @State private var referenceDraft: String = ""
    @State private var translation: String = "kjv"
    @State private var rebuildTask: Task<Void, Never>?

    private var translations: [BibleSeeder.BundledTranslation] {
        BibleSeeder.bundledTranslations()
    }

    /// True when the user has typed something we can't resolve. Surfaced as a
    /// soft warning rather than blocking edits — the field stays sticky so they
    /// can finish typing without their input vanishing.
    private var parsedReference: BibleReference? {
        BibleReferenceParser.parse(referenceDraft)
    }

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $item.title)
                TextField("Reference (e.g. John 3:16-18)", text: $referenceDraft)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: referenceDraft) { _, _ in scheduleRebuild() }
                Picker("Translation", selection: $translation) {
                    ForEach(translations) { t in
                        Text(t.displayName).tag(t.id)
                    }
                }
                .onChange(of: translation) { _, _ in
                    scheduleRebuild(immediate: true)
                }
            } header: {
                Text("Bible")
            } footer: {
                footerText
            }

            Section("Derived slides") {
                LabeledContent("Slides", value: "\(item.orderedSlides.count)")
                if let parsed = parsedReference {
                    LabeledContent("Lookup", value: parsed.displayText)
                }
                if ContentRebuilder.hasManualEdits(item) {
                    Button(role: .destructive) {
                        ContentRebuilder.resetToAutoDerived(item)
                        live.arm(LiveState.programSlides(for: item))
                    } label: {
                        Label("Restore auto-generated slides", systemImage: "arrow.uturn.backward")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            referenceDraft = item.bibleReference ?? ""
            translation = (item.bibleTranslation ?? translations.first?.id ?? "kjv").lowercased()
        }
        .onChange(of: item.persistentModelID) { _, _ in
            referenceDraft = item.bibleReference ?? ""
            translation = (item.bibleTranslation ?? translations.first?.id ?? "kjv").lowercased()
        }
        .onDisappear {
            rebuildTask?.cancel()
            ContentRebuilder.setBibleReference(referenceDraft, translation: translation, on: item)
        }
    }

    /// Status line under the reference field. Always renders some text so the
    /// surrounding `Section { … } footer:` body has a stable shape; SwiftUI
    /// dislikes empty `if` branches at the top level of a view builder.
    @ViewBuilder private var footerText: some View {
        if !referenceDraft.isEmpty && parsedReference == nil {
            Text("Couldn't parse that reference. Try `John 3:16` or `Psalm 23`.")
                .font(.caption).foregroundStyle(.orange)
        } else if let parsed = parsedReference, item.orderedSlides.isEmpty {
            Text("`\(parsed.displayText)` isn't in the bundled \(translation.uppercased()) yet.")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            Text("Bundled translations cover only the Phase 7 starter passages (John 3, Psalm 23, Rom 8:28, Phil 4:13). Drop OSIS files in via Tools/build-bible-db for more.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func scheduleRebuild(immediate: Bool = false) {
        rebuildTask?.cancel()
        if immediate {
            ContentRebuilder.setBibleReference(referenceDraft, translation: translation, on: item)
            live.arm(LiveState.programSlides(for: item))
            return
        }
        rebuildTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            ContentRebuilder.setBibleReference(referenceDraft, translation: translation, on: item)
            live.arm(LiveState.programSlides(for: item))
        }
    }
}
