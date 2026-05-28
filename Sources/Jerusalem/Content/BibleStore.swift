import Foundation
import SwiftData

/// Read-side lookup for ``BibleVerse`` rows. The store is read-only after the
/// initial seed (``BibleSeeder``); editing scripture is out of scope.
///
/// Pure, ``@MainActor`` namespace so the existing main-thread SwiftData rules
/// hold and the caller doesn't have to think about contexts.
@MainActor
enum BibleStore {

    /// Fetches verses for `reference` in `translation` from the given context,
    /// ordered by verse number. Empty result means "not seeded" — the editor
    /// surfaces this as an unknown-reference state.
    static func verses(for reference: BibleReference,
                       translation: String,
                       in context: ModelContext) -> [BibleVerse] {
        let book = reference.book
        let chapter = reference.chapter
        let translationKey = translation.lowercased()

        if let range = reference.verses {
            let low = range.lowerBound
            let high = range.upperBound
            let descriptor = FetchDescriptor<BibleVerse>(
                predicate: #Predicate { verse in
                    verse.translation == translationKey
                    && verse.book == book
                    && verse.chapter == chapter
                    && verse.number >= low
                    && verse.number <= high
                },
                sortBy: [SortDescriptor(\.number)])
            return (try? context.fetch(descriptor)) ?? []
        }

        let descriptor = FetchDescriptor<BibleVerse>(
            predicate: #Predicate { verse in
                verse.translation == translationKey
                && verse.book == book
                && verse.chapter == chapter
            },
            sortBy: [SortDescriptor(\.number)])
        return (try? context.fetch(descriptor)) ?? []
    }

    /// True once any verse has been inserted for `translation`. Used by
    /// ``BibleSeeder`` to decide whether to load the starter dataset.
    static func isSeeded(translation: String, in context: ModelContext) -> Bool {
        let translationKey = translation.lowercased()
        var descriptor = FetchDescriptor<BibleVerse>(
            predicate: #Predicate { $0.translation == translationKey })
        descriptor.fetchLimit = 1
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }
}
