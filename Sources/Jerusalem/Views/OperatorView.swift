import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

/// The operator (live control) window. Drives the live program from the keyboard
/// (arrow/space + Black/Clear/Logo), search, and slide clicks. All editing —
/// title, content, and slide design — happens in the separate slide-editor
/// window (Phase 8.5); this window is presentation/live-control only.
struct OperatorView: View {

    @Query(sort: \Item.title) private var items: [Item]
    @Query(sort: \Playlist.name) private var playlists: [Playlist]

    @Environment(LiveState.self) private var live
    @Environment(OutputController.self) private var output
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow

    @State private var showInspector = true
    @State private var searchText = ""
    @State private var selectedID: PersistentIdentifier?
    @State private var program: [LiveState.ProgramSlide] = []
    @State private var keyMonitor: Any?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    /// Identity of this operator window, so the key monitor can tell when the
    /// operator (vs. an editor window) is key. See ``installKeyMonitor``.
    @State private var windowRef = WindowRef()

    private var filteredItems: [Item] {
        searchText.isEmpty ? items
            : items.filter { LibrarySearch.matches(title: $0.title, query: searchText) }
    }
    private var selectedItem: Item? { items.first { $0.persistentModelID == selectedID } }
    private var selectedPlaylist: Playlist? { playlists.first { $0.persistentModelID == selectedID } }
    private var detailTitle: String { selectedItem?.title ?? selectedPlaylist?.name ?? "" }
    private var detailSubtitle: String { program.isEmpty ? "" : "\(program.count) slides" }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(items: filteredItems, playlists: playlists, selection: $selectedID)
                .navigationSplitViewColumnWidth(min: 200, ideal: 228, max: 320)
        } detail: {
            slideGrid
                .inspector(isPresented: $showInspector) {
                    InspectorView(item: selectedItem)
                        .inspectorColumnWidth(min: 280, ideal: 320, max: 380)
                }
                .toolbar { toolbarContent }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search & go live…")
        .frame(minWidth: 960, minHeight: 600)
        .onReceive(NotificationCenter.default.publisher(for: .slideEditorDidClose)) { _ in
            // The editor edits the live model in its own window; once it closes
            // we re-arm the program so the operator grid + audience output pick
            // up the edits. `rebuildProgram()` is idempotent.
            rebuildProgram()
        }
        .onChange(of: selectedID) { _, _ in
            rebuildProgram()
            persistSelection()
        }
        .onChange(of: live.liveSlideID) { _, _ in
            VideoPrewarmer.shared.prewarm(live.nextProgramSlide?.videoCue)
            // Render-ahead the next slide at output resolution so advancing
            // doesn't pay for a fresh `SlideRenderer.makeImage` mid-switch.
            if let next = live.nextProgramSlide?.renderable {
                SlidePrewarmer.shared.prewarm(next, pixelSize: output.activeOutputPixelSize)
            }
        }
        .onAppear {
            // Restore the last operator selection so reopening lands where the
            // service left off — selection only, not auto-go-live.
            if selectedID == nil {
                selectedID = LastPosition.resolve(LastPosition.load(), in: modelContext)
            }
            rebuildProgram()
            installKeyMonitor()
        }
        .onDisappear(perform: removeKeyMonitor)
        .background(WindowAccessor { windowRef.window = $0 })
    }

    /// Saves the current selection as `Item` / `Playlist` UUID — survives the
    /// PersistentIdentifier reset that happens on relaunch.
    private func persistSelection() {
        if let item = selectedItem {
            LastPosition.save(.item(item.uuid))
        } else if let playlist = selectedPlaylist {
            LastPosition.save(.playlist(playlist.uuid))
        } else {
            LastPosition.save(nil)
        }
    }

    private func rebuildProgram() {
        if let selectedItem {
            program = LiveState.programSlides(for: selectedItem)
        } else if let selectedPlaylist {
            program = LiveState.programSlides(for: selectedPlaylist)
        } else {
            program = []
        }
        live.arm(program)
        VideoPrewarmer.shared.prewarm(live.nextProgramSlide?.videoCue)
    }

    /// The operator detail pane is always the slide grid now — all editing moved
    /// to the slide-editor window (Phase 8.5).
    private var slideGrid: some View {
        SlideGridView(title: detailTitle, subtitle: detailSubtitle,
                      slides: program, liveSlideID: live.liveSlideID,
                      onActivate: { live.goLive(id: $0) },
                      onEdit: openSlideEditor)
    }

    /// Opens the slide editor for the selected item (the editor is keyed on the
    /// item now, so it works even before any slides exist). Reopening the same
    /// item raises its existing window.
    private func openEditor(for item: Item?) {
        guard let item else { return }
        openWindow(id: "slide-editor", value: item.persistentModelID)
    }

    /// Grid "Edit Slide…" / double-click passes a *program slide* id; resolve it
    /// to the parent item and open that item's editor. Media program ids resolve
    /// to the item directly; otherwise fall back to the current selection.
    private func openSlideEditor(id: PersistentIdentifier) {
        if let slide = modelContext.model(for: id) as? Slide, let item = slide.item {
            openWindow(id: "slide-editor", value: item.persistentModelID)
        } else if modelContext.model(for: id) is Item {
            openWindow(id: "slide-editor", value: id)
        } else {
            openEditor(for: selectedItem)
        }
    }

    /// Window-local key monitor: arrows/space navigate, B/C/L panic. Ignored while a
    /// text field (e.g. the search box) is focused, so typing still works.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        let live = self.live
        let windowRef = self.windowRef
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                // Only drive the live program from the operator window. Since the
                // Phase 8.4 editor is its own window, arrows/space/B-C-L pressed
                // while it (or any other window) is key must pass through —
                // editing must never advance or blank the audience output.
                guard NSApp.keyWindow === windowRef.window else { return event }
                if NSApp.keyWindow?.firstResponder is NSText { return event }
                switch event.keyCode {
                case 49, 124, 125: live.next(); return nil          // space, →, ↓
                case 123, 126: live.previous(); return nil           // ←, ↑
                default: break
                }
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "b": live.setPanic(.black); return nil
                case "c": live.setPanic(.clear); return nil
                case "l": live.setPanic(.logo); return nil
                default: return event
                }
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { openEditor(for: selectedItem) } label: {
                Label("Edit", systemImage: "square.and.pencil")
            }
            .help("Edit this item — title, content, and slide design")
            .disabled(selectedItem == nil)
        }
        ToolbarItem(placement: .status) {
            Menu {
                if output.isActive {
                    Button("Stop Output", systemImage: "stop.fill") { output.stop() }
                    Divider()
                }
                if output.screens.isEmpty {
                    Text("No displays detected")
                } else {
                    ForEach(output.screens) { screen in
                        Button { output.start(screenID: screen.id) } label: {
                            Label(screen.name, systemImage: "display")
                        }
                    }
                }
            } label: {
                Label(output.isActive ? output.activeScreenName : "Start Output",
                      systemImage: output.isActive ? "tv.fill" : "tv")
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Button("New Song", systemImage: "music.note") { newAuthoredItem(kind: .song) }
                Button("New Bible", systemImage: "book.closed") { newAuthoredItem(kind: .bible) }
                Button("New Text", systemImage: "text.alignleft") { newAuthoredItem(kind: .text) }
                Divider()
                Button("Import Media…", systemImage: "square.and.arrow.down") { importMedia() }
            } label: {
                Label("Add", systemImage: "plus")
            }
            Button { showInspector.toggle() } label: { Label("Inspector", systemImage: "sidebar.trailing") }
        }
    }

    /// Inserts a fresh song, sermon/text, or Bible item seeded with the default
    /// theme and the right authoring scaffolding, selects it, and opens the slide
    /// editor on it so the operator can start authoring immediately.
    private func newAuthoredItem(kind: ItemKind) {
        let title: String
        switch kind {
        case .song:  title = "Untitled Song"
        case .bible: title = "Untitled Passage"
        case .text:  title = "Untitled Text"
        case .media: return
        }
        let item = Item(kind: kind, title: title)
        item.theme = Theme.makeDefault()
        item.linesPerSlide = kind == .song ? 2 : 3
        modelContext.insert(item)
        switch kind {
        case .song:
            item.songSections = [SongSection(kind: .verse, number: 1, order: 0, lyrics: "")]
        case .bible:
            item.bibleTranslation = BibleSeeder.bundledTranslations().first?.id ?? "kjv"
            item.bibleReference = ""
        case .text:
            item.bodyText = ""
        case .media:
            break
        }
        selectedID = item.persistentModelID
        openEditor(for: item)
    }

    /// Opens a file picker, copies the chosen clip or image into the media library,
    /// and adds it to the content library as a media item.
    private func importMedia() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie, .image]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let filename = try MediaStorage.importFile(at: url)
            let item = Item(kind: .media, title: url.deletingPathExtension().lastPathComponent)
            item.mediaFilename = filename
            modelContext.insert(item)
        } catch {
            NSSound.beep()
        }
    }
}

/// Weak holder for a window reference, captured by the key monitor closure so it
/// reads the *current* window identity at fire time (not whatever it was at
/// install time).
final class WindowRef {
    weak var window: NSWindow?
}

/// Resolves the `NSWindow` hosting a SwiftUI view and reports it back. Used to
/// learn the operator window's identity without an `NSWindowDelegate`.
struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onResolve(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onResolve(nsView.window) }
    }
}

#Preview {
    let live = LiveState()
    return OperatorView()
        .modelContainer(Persistence.makeContainer(inMemory: true))
        .environment(live)
        .environment(OutputController(live: live))
}
