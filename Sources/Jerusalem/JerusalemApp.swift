import SwiftUI
import SwiftData

/// Entry point for Jerusalem — a native, macOS-only church presentation app.
///
/// Phase 3 adds the live audience output: a separate window (full-screen on an
/// external display) driven by ``LiveState``, independent of editing. See
/// `docs/IMPLEMENTATION-PLAN.md`.
@main
struct JerusalemApp: App {
    @State private var live: LiveState
    @State private var output: OutputController
    private let container = Persistence.makeContainer()

    init() {
        let liveState = LiveState()
        _live = State(initialValue: liveState)
        _output = State(initialValue: OutputController(live: liveState))
    }

    var body: some Scene {
        WindowGroup("Jerusalem", id: "operator") {
            OperatorView()
                .environment(live)
                .environment(output)
        }
        .defaultSize(width: 1280, height: 800)
        .windowToolbarStyle(.unified)
        .modelContainer(container)

        // Phase 8.5: the slide editor is its own window (real traffic lights +
        // unified toolbar) and the single place to edit an item — title, content,
        // and slide design. Opened from the operator via `openWindow(id:value:)`
        // carrying the *item's* `PersistentIdentifier` (so it opens even before
        // any slides exist). Shares the same model container, so edits are
        // reflected back on close.
        WindowGroup("Slide Editor", id: "slide-editor", for: PersistentIdentifier.self) { $itemID in
            SlideEditorWindowRoot(itemID: itemID)
                .environment(live)
                .environment(output)
        }
        .defaultSize(width: 1320, height: 820)
        .windowToolbarStyle(.unified)
        .modelContainer(container)
    }
}
