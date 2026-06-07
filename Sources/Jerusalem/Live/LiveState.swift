import SwiftUI
import SwiftData

/// Owns the live program and the audience output state.
///
/// The output reads only the resolved ``content`` (a value snapshot), never a live
/// model — so editing never changes what's on screen until the operator acts. A
/// program is *armed* (loaded) without changing output; the operator *starts* it by
/// pressing a navigation key or clicking a slide.
@MainActor
@Observable
final class LiveState {

    /// One navigable item in the live program: either a rendered slide or a video
    /// clip (a value snapshot + its identity).
    struct ProgramSlide: Identifiable, Equatable {
        let id: PersistentIdentifier
        let kind: Kind
        let sectionLabel: String?

        enum Kind: Equatable {
            case slide(RenderableSlide)
            case video(VideoCue)
        }

        var renderable: RenderableSlide? {
            if case .slide(let renderable) = kind { return renderable }
            return nil
        }
        var videoCue: VideoCue? {
            if case .video(let cue) = kind { return cue }
            return nil
        }
    }

    /// One titled section of a playlist's program — the slides of a single entry's
    /// item, used to render the grouped slide grid. Keyed on the `PlaylistEntry`'s
    /// id so the same item appearing in two entries forms two distinct groups.
    struct ProgramGroup: Identifiable, Equatable {
        let id: PersistentIdentifier
        let title: String
        let slides: [ProgramSlide]
    }

    enum Panic: Equatable { case none, black, clear, logo }
    enum Content: Equatable, Hashable { case empty, black, logo, slide(RenderableSlide), video(VideoCue) }

    private(set) var content: Content = .empty
    private(set) var program: [ProgramSlide] = []
    private(set) var index: Int = 0
    private(set) var started: Bool = false
    private(set) var panic: Panic = .none
    var transition: TransitionStyle = .fade

    var hasProgram: Bool { !program.isEmpty }

    /// The live item's identity, for grid highlighting (nil while panicked/idle).
    var liveSlideID: PersistentIdentifier? {
        guard started, panic == .none, program.indices.contains(index) else { return nil }
        return program[index].id
    }

    /// The item a "next" press will reveal — for the inspector's Next preview.
    var nextProgramSlide: ProgramSlide? {
        let next = started ? index + 1 : 0
        return program.indices.contains(next) ? program[next] : nil
    }

    var nextRenderable: RenderableSlide? { nextProgramSlide?.renderable }

    // MARK: Program control

    /// Loads a program without changing the output (arms it).
    func arm(_ slides: [ProgramSlide]) {
        program = slides
        index = 0
        started = false
        panic = .none
        recompute()
    }

    func goLive(id: PersistentIdentifier) {
        guard let position = program.firstIndex(where: { $0.id == id }) else { return }
        index = position
        started = true
        panic = .none
        recompute()
    }

    func next() {
        guard hasProgram else { return }
        if panic != .none {
            panic = .none                       // a nav key resumes from a panic state
        } else if !started {
            started = true
            index = 0                           // first press starts the program
        } else {
            index = min(index + 1, program.count - 1)
        }
        recompute()
    }

    func previous() {
        guard hasProgram, started else { return }
        if panic != .none {
            panic = .none
        } else {
            index = max(index - 1, 0)
        }
        recompute()
    }

    func setPanic(_ requested: Panic) {
        panic = (panic == requested) ? .none : requested   // toggle
        recompute()
    }

    func clear() {
        program = []
        index = 0
        started = false
        panic = .none
        recompute()
    }

    private func recompute() {
        switch panic {
        case .black:
            content = .black
        case .logo:
            content = .logo
        case .clear where started && program.indices.contains(index):
            content = clearedContent(of: program[index])
        case .none where started && program.indices.contains(index):
            content = liveContent(of: program[index])
        default:
            content = .empty
        }
    }

    private func liveContent(of slide: ProgramSlide) -> Content {
        switch slide.kind {
        case .slide(let renderable): .slide(renderable)
        case .video(let cue): .video(cue)
        }
    }

    /// "Clear" strips text on a slide (background only); a clip has no text to clear.
    private func clearedContent(of slide: ProgramSlide) -> Content {
        switch slide.kind {
        case .slide(let renderable):
            .slide(RenderableSlide(backgroundColorHex: renderable.backgroundColorHex, elements: [],
                                   backgroundVideo: renderable.backgroundVideo))
        case .video(let cue):
            .video(cue)
        }
    }

    // MARK: Building programs

    static func programSlides(for item: Item) -> [ProgramSlide] {
        if item.kind == .media {
            guard let filename = item.mediaFilename else { return [] }
            switch MediaImport.kind(forExtension: (filename as NSString).pathExtension) {
            case .video:
                let cue = VideoCue(url: MediaStorage.url(forFilename: filename),
                                   loops: item.videoLoops,
                                   muted: item.videoMuted,
                                   endBehavior: item.videoEndBehavior)
                return [ProgramSlide(id: item.persistentModelID, kind: .video(cue), sectionLabel: item.title)]
            case .image:
                let renderable = RenderableSlide(backgroundColorHex: "#000000", elements: [],
                                                 backgroundImageURL: MediaStorage.url(forFilename: filename))
                return [ProgramSlide(id: item.persistentModelID, kind: .slide(renderable), sectionLabel: item.title)]
            case nil:
                return []
            }
        }
        return item.orderedSlides.map {
            ProgramSlide(id: $0.persistentModelID,
                         kind: .slide(RenderableSlide($0)),
                         sectionLabel: $0.sectionLabel)
        }
    }

    static func programSlides(for playlist: Playlist) -> [ProgramSlide] {
        playlist.orderedEntries.compactMap(\.item).flatMap(programSlides(for:))
    }

    /// The playlist's program split into one titled group per entry, in running
    /// order. `groupedProgram(for:).flatMap(\.slides)` equals
    /// `programSlides(for: playlist)`, so the grouped grid and the armed flat
    /// program share slide identities (click-to-go-live + live highlight align).
    static func groupedProgram(for playlist: Playlist) -> [ProgramGroup] {
        playlist.orderedEntries.compactMap { entry in
            entry.item.map {
                ProgramGroup(id: entry.persistentModelID,
                             title: $0.title,
                             slides: programSlides(for: $0))
            }
        }
    }
}

enum TransitionStyle: String, CaseIterable, Identifiable {
    case cut, fade
    var id: String { rawValue }
    var label: String { self == .cut ? "Cut" : "Fade" }
}
