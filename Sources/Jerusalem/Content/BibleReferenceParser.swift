import Foundation

/// A parsed scripture reference: `John 3:16-18` → `BibleReference("John", 3, 16...18)`.
/// `nil` verses means "the whole chapter."
struct BibleReference: Equatable, Sendable {
    var book: String
    var chapter: Int
    var verses: ClosedRange<Int>?

    /// Human-facing form (`"John 3:16"`, `"John 3:16-18"`, `"Psalms 23"`). Used
    /// as the slide section label so the operator always sees what's projected.
    var displayText: String {
        guard let verses else { return "\(book) \(chapter)" }
        if verses.lowerBound == verses.upperBound {
            return "\(book) \(chapter):\(verses.lowerBound)"
        }
        return "\(book) \(chapter):\(verses.lowerBound)-\(verses.upperBound)"
    }
}

/// Parses free-typed scripture references. Tolerant of case, whitespace, and
/// common abbreviations (via ``BibleBookCatalog``); rejects malformed input by
/// returning nil so the editor can show a clean "unknown reference" state.
///
/// Pure (no model/UI dependencies) — caseless `enum` namespace per project
/// convention.
enum BibleReferenceParser {

    /// Parses inputs like:
    /// - `John 3:16` → John 3:16
    /// - `John 3:16-18` → John 3:16…18
    /// - `Psalm 23` → Psalms 23 (whole chapter; `verses == nil`)
    /// - `1 Corinthians 13:4-7` → 1 Corinthians 13:4…7
    /// - `1cor 13` → 1 Corinthians 13
    ///
    /// Requires whitespace between the book name and the chapter[:verses] spec.
    static func parse(_ input: String) -> BibleReference? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        guard tokens.count >= 2 else { return nil }

        guard let (chapter, verses) = parseChapterVerses(tokens.last!) else { return nil }
        let bookInput = tokens.dropLast().joined(separator: " ")
        guard let book = BibleBookCatalog.canonical(for: bookInput) else { return nil }

        guard chapter > 0 else { return nil }
        if let verses, verses.lowerBound < 1 { return nil }
        return BibleReference(book: book, chapter: chapter, verses: verses)
    }

    /// Parses the trailing token: `13`, `13:4`, or `13:4-7`. Returns nil for
    /// anything else.
    private static func parseChapterVerses(_ token: String) -> (Int, ClosedRange<Int>?)? {
        if let colon = token.firstIndex(of: ":") {
            guard let chapter = Int(token[..<colon]) else { return nil }
            let versesPart = token[token.index(after: colon)...]
            if let dash = versesPart.firstIndex(of: "-") {
                guard let start = Int(versesPart[..<dash]),
                      let end = Int(versesPart[versesPart.index(after: dash)...]),
                      start <= end
                else { return nil }
                return (chapter, start...end)
            }
            guard let single = Int(versesPart) else { return nil }
            return (chapter, single...single)
        }
        guard let chapter = Int(token) else { return nil }
        return (chapter, nil)
    }
}
