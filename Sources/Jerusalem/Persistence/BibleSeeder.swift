import Foundation
import SwiftData

/// One-shot loader for the bundled Bible dataset. Runs on first launch (or
/// whenever the store is missing a particular translation) and inserts
/// ``BibleVerse`` rows so ``BibleStore`` can serve them offline.
///
/// The dataset shipped today is a starter — John 3, Psalm 23, Rom 8:28, Phil 4:13
/// in KJV + WEB — enough for the Phase 7 gate. Drop a full KJV/WEB OSIS export
/// in via `Tools/build-bible-db` to replace `bible-starter.json` with a fuller
/// corpus; the seeder doesn't care how big the file gets.
enum BibleSeeder {

    /// Inserts any translations from the bundled starter that aren't already in
    /// the store. Idempotent — running it twice in a row is a no-op.
    @MainActor
    static func seedIfNeeded(_ context: ModelContext) {
        guard let starter = loadStarter() else { return }
        for translation in starter.translations {
            let key = translation.id.lowercased()
            if BibleStore.isSeeded(translation: key, in: context) { continue }
            for verse in translation.verses {
                context.insert(BibleVerse(
                    translation: key,
                    book: verse.book,
                    chapter: verse.chapter,
                    number: verse.number,
                    text: verse.text))
            }
        }
        try? context.save()
    }

    /// Public-domain translations bundled in this build, for the editor's picker.
    /// Reading from the bundled JSON keeps the source list in lockstep with the
    /// shipped data — the editor never offers a translation we can't look up.
    static func bundledTranslations() -> [BundledTranslation] {
        loadStarter()?.translations.map {
            BundledTranslation(id: $0.id.lowercased(), displayName: $0.displayName)
        } ?? []
    }

    /// Value-type pair surfaced to UI code.
    struct BundledTranslation: Hashable, Identifiable, Sendable {
        var id: String
        var displayName: String
    }

    // MARK: - Internals

    private struct Starter: Decodable {
        var translations: [TranslationBlock]
    }
    private struct TranslationBlock: Decodable {
        var id: String
        var displayName: String
        var verses: [VerseRecord]
    }
    private struct VerseRecord: Decodable {
        var book: String
        var chapter: Int
        var number: Int
        var text: String
    }

    private static func loadStarter() -> Starter? {
        // Resolve against the bundle that ships the Jerusalem module — that's the
        // app bundle in release, and the same when tests `@testable import` it.
        // Falls back to `.main` so callers running the code from elsewhere still
        // get a chance.
        let candidates: [Bundle] = [Bundle(for: BibleVerse.self), .main]
        for bundle in candidates {
            if let url = bundle.url(forResource: "bible-starter", withExtension: "json"),
               let data = try? Data(contentsOf: url),
               let starter = try? JSONDecoder().decode(Starter.self, from: data) {
                return starter
            }
        }
        return nil
    }
}
