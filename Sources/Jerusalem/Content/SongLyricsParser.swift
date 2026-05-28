import Foundation

/// A section parsed from a free-form lyrics block. The value type is decoupled from
/// SwiftData so the parser is trivially unit-testable; ``ContentRebuilder`` turns
/// these into ``SongSection`` rows.
struct ParsedSongSection: Equatable, Sendable {
    var kind: SongSectionKind
    var number: Int?
    var lyrics: String
}

/// Parses lyrics blocks like:
///
///     [Verse 1]
///     Amazing grace! How sweet the sound
///     That saved a wretch like me!
///
///     [Chorus]
///     My chains are gone, I've been set free
///
/// into ordered ``ParsedSongSection`` values. Markers are case-insensitive and
/// whitespace-tolerant; content before the first marker is treated as an unnumbered
/// Verse so a bare lyrics paste still produces a working song.
///
/// Pure (no model/UI dependencies) — extracted as a caseless `enum` namespace per
/// project convention so behavior tests don't need SwiftData or AppKit.
enum SongLyricsParser {

    /// All section kinds we recognize, keyed by the lowercased word inside `[...]`.
    private static let kindAliases: [String: SongSectionKind] = [
        "verse":  .verse,
        "chorus": .chorus,
        "bridge": .bridge,
        "tag":    .tag,
    ]

    static func parse(_ text: String) -> [ParsedSongSection] {
        var sections: [ParsedSongSection] = []
        var currentKind: SongSectionKind = .verse
        var currentNumber: Int? = nil
        var currentLines: [String] = []
        var sawMarker = false

        func flush() {
            // Drop leading/trailing blank lines; collapse a fully empty block.
            let trimmed = currentLines
                .drop(while: { $0.trimmingCharacters(in: .whitespaces).isEmpty })
                .reversed()
                .drop(while: { $0.trimmingCharacters(in: .whitespaces).isEmpty })
                .reversed()
            let lyrics = trimmed.joined(separator: "\n")
            // Only the implicit pre-marker section is allowed to be empty — and we
            // skip it entirely. Explicit markers always create a section even with
            // no lyrics, so the editor can show empty sections the operator added.
            if lyrics.isEmpty && !sawMarker { return }
            sections.append(ParsedSongSection(kind: currentKind, number: currentNumber, lyrics: lyrics))
        }

        for rawLine in text.components(separatedBy: .newlines) {
            if let parsed = parseMarker(rawLine) {
                flush()
                currentKind = parsed.kind
                currentNumber = parsed.number
                currentLines = []
                sawMarker = true
            } else {
                currentLines.append(rawLine)
            }
        }
        flush()
        return sections
    }

    /// Recognizes a single-line section marker like `[Verse 1]`, `[chorus]`,
    /// `[ Bridge ]`. Returns nil for any other line.
    static func parseMarker(_ line: String) -> (kind: SongSectionKind, number: Int?)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else { return nil }
        let inner = trimmed.dropFirst().dropLast()
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        guard !inner.isEmpty else { return nil }

        let parts = inner.split(whereSeparator: { $0.isWhitespace })
        guard let head = parts.first.map(String.init),
              let kind = kindAliases[head] else { return nil }

        let number: Int? = parts.count >= 2 ? Int(parts[1]) : nil
        return (kind, number)
    }

    /// Serializes parsed sections back into the editor format. Useful as the
    /// canonical re-pretty-print after a rebuild.
    static func format(_ sections: [ParsedSongSection]) -> String {
        sections.map { section in
            let header = section.number.map { "[\(section.kind.displayName) \($0)]" }
                ?? "[\(section.kind.displayName)]"
            return section.lyrics.isEmpty ? header : "\(header)\n\(section.lyrics)"
        }.joined(separator: "\n\n")
    }
}
