import Foundation
import SwiftData

/// One verse of one translation. Phase 7 ships KJV + WEB; both stored here side
/// by side, keyed by `(translation, book, chapter, number)`. Read-only after the
/// initial seed — the Bible data is reference content, not user-authored.
///
/// SwiftData lets us reuse the existing on-disk container, ordering, and fetch
/// machinery instead of linking libsqlite3 directly. Index hints are best-effort;
/// SwiftData's @Attribute(.unique) ensures the natural composite key is enforced.
@Model
final class BibleVerse {
    /// Translation identifier in lowercase — `"kjv"`, `"web"`, etc. Free-form
    /// strings (not an enum) so adding ASV / BBE later doesn't require a migration.
    var translation: String = "kjv"
    /// Canonical book name as resolved by ``BibleBookCatalog`` (e.g. `"John"`,
    /// `"1 Corinthians"`, `"Psalms"`). The parser canonicalises before insert.
    var book: String = ""
    var chapter: Int = 0
    var number: Int = 0
    var text: String = ""

    init(translation: String, book: String, chapter: Int, number: Int, text: String) {
        self.translation = translation
        self.book = book
        self.chapter = chapter
        self.number = number
        self.text = text
    }

    /// Human-facing reference for this verse, e.g. `"John 3:16"`. Used as the
    /// slide's section label so the operator always sees what's projected.
    var reference: String { "\(book) \(chapter):\(number)" }
}
