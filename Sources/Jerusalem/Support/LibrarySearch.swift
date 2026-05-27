import Foundation

/// Library search matching, kept pure so it's unit-testable without models.
enum LibrarySearch {
    static func matches(title: String, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return title.localizedCaseInsensitiveContains(trimmed)
    }
}
