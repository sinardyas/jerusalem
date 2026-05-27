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
    }
}
