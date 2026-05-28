import Foundation
import SwiftData

/// The structural role of a song section. Followed by SwiftData's `…Raw: String`
/// convention so the column stays a primitive while callers read a typed enum.
enum SongSectionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case verse, chorus, bridge, tag
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .verse:  "Verse"
        case .chorus: "Chorus"
        case .bridge: "Bridge"
        case .tag:    "Tag"
        }
    }
}

/// A block of raw lyrics belonging to one ``Item`` (song). Sections are the *authored*
/// source of truth for songs; the rendered slides on the same ``Item`` are derived
/// from these via ``ContentRebuilder``. Storing the original lyrics verbatim means
/// the operator can change the lines-per-slide setting without losing line breaks.
@Model
final class SongSection {
    var order: Int = 0
    private var kindRaw: String = SongSectionKind.verse.rawValue
    /// Optional ordinal, used to disambiguate repeated kinds (e.g. "Verse 2").
    /// Conventionally only verses are numbered, but the model doesn't restrict it.
    var number: Int?
    /// Raw multi-line lyrics text for this section, newline-separated.
    var lyrics: String = ""

    var item: Item?

    init(kind: SongSectionKind, number: Int? = nil, order: Int = 0, lyrics: String = "") {
        self.kindRaw = kind.rawValue
        self.number = number
        self.order = order
        self.lyrics = lyrics
    }

    var kind: SongSectionKind {
        get { SongSectionKind(rawValue: kindRaw) ?? .verse }
        set { kindRaw = newValue.rawValue }
    }

    /// The label that appears on the first slide of this section in the grid
    /// (e.g. "Verse 1", "Chorus"). Continuation slides intentionally have no label.
    var displayLabel: String {
        if let number { return "\(kind.displayName) \(number)" }
        return kind.displayName
    }
}
