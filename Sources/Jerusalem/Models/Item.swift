import Foundation
import SwiftData

/// The kind of content an ``Item`` represents.
enum ItemKind: String, Codable, CaseIterable, Identifiable {
    case song, bible, text, media
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .song:  "Song"
        case .bible: "Bible"
        case .text:  "Text"
        case .media: "Media"
        }
    }

    var symbolName: String {
        switch self {
        case .song:  "music.note"
        case .bible: "book.closed"
        case .text:  "text.alignleft"
        case .media: "photo.on.rectangle"
        }
    }
}

/// A single piece of presentable content in the library — a song, a Bible passage,
/// a text/sermon item, or a media clip — together with the ordered slides it produces.
@Model
final class Item {
    /// Stable external identifier (distinct from SwiftData's `persistentModelID`),
    /// useful later for media file naming, export, and sync.
    var uuid: UUID = UUID()

    private var kindRaw: String = ItemKind.text.rawValue
    var title: String = ""
    var subtitle: String?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    // Type-specific metadata (only the relevant fields are used per kind).
    var ccli: String?              // song
    var bibleReference: String?    // bible, e.g. "John 3:16-18"
    var bibleTranslation: String?  // bible, e.g. "KJV"
    var mediaFilename: String?     // media (stored under MediaStorage.directory)
    var videoLoops: Bool = false           // media: loop the clip
    var videoMuted: Bool = false           // media: mute audio
    private var videoEndBehaviorRaw: String = VideoEndBehavior.hold.rawValue

    // Authoring controls for song/text items.
    /// Maximum number of lyric/body lines that fit on a single derived slide.
    /// Used by ``ContentRebuilder`` when re-materializing slides from sections.
    var linesPerSlide: Int = 2
    /// Body text for sermon/text items, paragraph-separated by blank lines.
    /// Songs use ``songSections`` instead; this stays nil for them.
    var bodyText: String?

    /// Output aspect ratio for this item's slides. Encoded as `"16:9"` or `"4:3"`
    /// (nil means default to 16:9). The Phase 8.2.3 toolbar picker writes here;
    /// the canvas and renderer read it back via ``aspectRatioValue``.
    var aspectRatio: String?

    @Relationship(deleteRule: .cascade, inverse: \Slide.item)
    var slides: [Slide] = []

    @Relationship(deleteRule: .cascade, inverse: \SongSection.item)
    var songSections: [SongSection] = []

    @Relationship(deleteRule: .cascade, inverse: \PlaylistEntry.item)
    var playlistEntries: [PlaylistEntry] = []

    var theme: Theme?

    init(kind: ItemKind, title: String, subtitle: String? = nil) {
        self.kindRaw = kind.rawValue
        self.title = title
        self.subtitle = subtitle
    }

    var kind: ItemKind {
        get { ItemKind(rawValue: kindRaw) ?? .text }
        set { kindRaw = newValue.rawValue }
    }

    var videoEndBehavior: VideoEndBehavior {
        get { VideoEndBehavior(rawValue: videoEndBehaviorRaw) ?? .hold }
        set { videoEndBehaviorRaw = newValue.rawValue }
    }

    /// Slides in presentation order.
    var orderedSlides: [Slide] {
        slides.sorted { $0.order < $1.order }
    }

    /// Sections in authored order — the source-of-truth view for songs.
    var orderedSongSections: [SongSection] {
        songSections.sorted { $0.order < $1.order }
    }

    /// Numeric aspect ratio derived from ``aspectRatio``. Defaults to 16:9 when
    /// missing or unparseable so the renderer can never end up dividing by zero.
    var aspectRatioValue: CGFloat {
        guard let raw = aspectRatio else { return 16.0 / 9.0 }
        let parts = raw.split(separator: ":")
        if parts.count == 2,
           let w = Double(parts[0]), let h = Double(parts[1]), h > 0 {
            return CGFloat(w / h)
        }
        return 16.0 / 9.0
    }
}
