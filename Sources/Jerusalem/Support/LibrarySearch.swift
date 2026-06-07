import Foundation

/// Library search matching, kept pure so it's unit-testable without models.
enum LibrarySearch {
    /// True if every whitespace-separated token in `query` is found somewhere in
    /// `text` (case-insensitive, order-independent). An empty query matches
    /// everything; a single-token query reduces to a plain substring match.
    static func matches(query: String, in text: String) -> Bool {
        let tokens = query.split(whereSeparator: \.isWhitespace)
        guard !tokens.isEmpty else { return true }
        return tokens.allSatisfy { text.localizedCaseInsensitiveContains($0) }
    }

    static func matches(title: String, query: String) -> Bool {
        matches(query: query, in: title)
    }
}
