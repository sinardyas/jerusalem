import Foundation

/// A value-type description of one slide to materialize: its section label (only
/// set on the first slide of a section so the grid header reads cleanly) and the
/// text it should display. ``ContentRebuilder`` turns these into SwiftData rows.
struct SlideDraft: Equatable, Sendable {
    /// Section header shown in the slide grid. Only the first slide of each
    /// section carries a label; continuation slides have nil so the operator
    /// doesn't see "Verse 1" repeated three times.
    var sectionLabel: String?
    var text: String
}

/// Pure rules for turning authored content (song sections, sermon body) into the
/// flat ordered slide list the renderer + LiveState already consume. Caseless enum
/// so behavior is testable without SwiftData.
enum SlideSplitter {

    // MARK: Songs

    /// Splits each parsed section into ≤`linesPerSlide`-line chunks, applying the
    /// section's display label to the *first* chunk only. Empty sections produce
    /// one empty-text placeholder slide so the operator can still navigate to them.
    static func split(songSections: [ParsedSongSection], linesPerSlide: Int) -> [SlideDraft] {
        let perSlide = max(1, linesPerSlide)
        var drafts: [SlideDraft] = []
        for section in songSections {
            let label = displayLabel(for: section)
            let chunks = chunkLines(section.lyrics, perSlide: perSlide)
            if chunks.isEmpty {
                drafts.append(SlideDraft(sectionLabel: label, text: ""))
                continue
            }
            for (index, chunk) in chunks.enumerated() {
                drafts.append(SlideDraft(sectionLabel: index == 0 ? label : nil, text: chunk))
            }
        }
        return drafts
    }

    // MARK: Bible

    /// One slide per verse: the verse text plus a small footer with the reference
    /// + translation so the audience always sees what's being projected. The
    /// renderer's auto-fit shrinks long verses to fit; we don't split a single
    /// verse across slides (the MVP renders prose at a fitted size rather than
    /// breaking it mid-sentence).
    static func split(bibleVerses: [BibleVerse], translation: String) -> [SlideDraft] {
        let footerTag = translation.uppercased()
        return bibleVerses.map { verse in
            let footer = "— \(verse.reference) (\(footerTag))"
            return SlideDraft(sectionLabel: verse.reference,
                              text: "\(verse.text)\n\n\(footer)")
        }
    }

    // MARK: Sermon / text

    /// A sermon/text item becomes a title slide followed by one slide per body
    /// paragraph. Paragraphs are blank-line-separated; long paragraphs are further
    /// split by `linesPerSlide` so a single block can never overflow.
    static func split(sermonTitle title: String, body: String, linesPerSlide: Int) -> [SlideDraft] {
        let perSlide = max(1, linesPerSlide)
        var drafts: [SlideDraft] = []

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            drafts.append(SlideDraft(sectionLabel: "Title", text: trimmedTitle))
        }

        let paragraphs = body
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for (paragraphIndex, paragraph) in paragraphs.enumerated() {
            let chunks = chunkLines(paragraph, perSlide: perSlide)
            for (chunkIndex, chunk) in chunks.enumerated() {
                let label = chunkIndex == 0 ? "Point \(paragraphIndex + 1)" : nil
                drafts.append(SlideDraft(sectionLabel: label, text: chunk))
            }
        }
        return drafts
    }

    // MARK: - Internals

    /// Builds the display label for a parsed section. Verses are always shown with
    /// their ordinal so the operator can tell V1 from V2 at a glance; other kinds
    /// only show their ordinal when the song has multiples of them.
    private static func displayLabel(for section: ParsedSongSection) -> String {
        if let number = section.number {
            return "\(section.kind.displayName) \(number)"
        }
        return section.kind.displayName
    }

    /// Splits a multi-line block into newline-joined chunks of at most `perSlide`
    /// non-empty lines each. Leading and trailing blank lines are dropped; blanks
    /// between non-blanks are kept (they're meaningful in hymn typography).
    private static func chunkLines(_ text: String, perSlide: Int) -> [String] {
        var lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \t")) }
        while lines.first?.isEmpty == true { lines.removeFirst() }
        while lines.last?.isEmpty == true { lines.removeLast() }
        guard !lines.isEmpty else { return [] }

        var chunks: [String] = []
        var current: [String] = []
        for line in lines {
            current.append(line)
            if current.count >= perSlide {
                chunks.append(current.joined(separator: "\n"))
                current = []
            }
        }
        if !current.isEmpty {
            chunks.append(current.joined(separator: "\n"))
        }
        return chunks
    }
}
