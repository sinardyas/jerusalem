import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

/// The operator (live control) window. Drives the live program from the keyboard
/// (arrow/space + Black/Clear/Logo), search, and slide clicks.
struct OperatorView: View {

    enum Mode: String, CaseIterable, Identifiable {
        case show = "Show"
        case edit = "Edit"
        var id: String { rawValue }
    }

    @Query(sort: \Item.title) private var items: [Item]
    @Query(sort: \Playlist.name) private var playlists: [Playlist]

    @Environment(LiveState.self) private var live
    @Environment(OutputController.self) private var output
    @Environment(\.modelContext) private var modelContext

    @State private var mode: Mode = .edit
    @State private var showInspector = true
    @State private var searchText = ""
    @State private var selectedID: PersistentIdentifier?
    @State private var program: [LiveState.ProgramSlide] = []
    @State private var keyMonitor: Any?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

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
            SlideGridView(title: detailTitle, subtitle: detailSubtitle,
                          slides: program, liveSlideID: live.liveSlideID,
                          onActivate: { live.goLive(id: $0) })
                .inspector(isPresented: $showInspector) {
                    InspectorView(item: selectedItem)
                        .inspectorColumnWidth(min: 280, ideal: 320, max: 380)
                }
                .toolbar { toolbarContent }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search & go live…")
        .frame(minWidth: 960, minHeight: 600)
        .onChange(of: selectedID) { _, _ in rebuildProgram() }
        .onChange(of: live.liveSlideID) { _, _ in
            VideoPrewarmer.shared.prewarm(live.nextProgramSlide?.videoCue)
        }
        .onAppear { rebuildProgram(); installKeyMonitor() }
        .onDisappear(perform: removeKeyMonitor)
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

    /// Window-local key monitor: arrows/space navigate, B/C/L panic. Ignored while a
    /// text field (e.g. the search box) is focused, so typing still works.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        let live = self.live
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
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
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
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
                Button("Import Media…", systemImage: "square.and.arrow.down") { importMedia() }
            } label: {
                Label("Add", systemImage: "plus")
            }
            Button { showInspector.toggle() } label: { Label("Inspector", systemImage: "sidebar.trailing") }
        }
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

#Preview {
    let live = LiveState()
    return OperatorView()
        .modelContainer(Persistence.makeContainer(inMemory: true))
        .environment(live)
        .environment(OutputController(live: live))
}
