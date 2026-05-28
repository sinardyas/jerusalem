import Foundation

/// The canonical 66-book Protestant Bible list plus common aliases. Drives the
/// reference parser, the splitter's labels, and any UI that needs to validate
/// or display a book name.
///
/// Pure (no model/UI dependencies) — caseless `enum` namespace per project
/// convention.
enum BibleBookCatalog {

    /// All 66 canonical books, in order. The string is also the canonical display
    /// form the rest of the app uses ("1 Corinthians", not "1Cor" or "1 cor").
    static let canonicalBooks: [String] = [
        // Old Testament — 39
        "Genesis", "Exodus", "Leviticus", "Numbers", "Deuteronomy",
        "Joshua", "Judges", "Ruth",
        "1 Samuel", "2 Samuel",
        "1 Kings", "2 Kings",
        "1 Chronicles", "2 Chronicles",
        "Ezra", "Nehemiah", "Esther",
        "Job", "Psalms", "Proverbs", "Ecclesiastes", "Song of Solomon",
        "Isaiah", "Jeremiah", "Lamentations", "Ezekiel", "Daniel",
        "Hosea", "Joel", "Amos", "Obadiah", "Jonah", "Micah",
        "Nahum", "Habakkuk", "Zephaniah", "Haggai", "Zechariah", "Malachi",
        // New Testament — 27
        "Matthew", "Mark", "Luke", "John", "Acts",
        "Romans",
        "1 Corinthians", "2 Corinthians",
        "Galatians", "Ephesians", "Philippians", "Colossians",
        "1 Thessalonians", "2 Thessalonians",
        "1 Timothy", "2 Timothy", "Titus", "Philemon",
        "Hebrews", "James",
        "1 Peter", "2 Peter",
        "1 John", "2 John", "3 John",
        "Jude", "Revelation",
    ]

    /// Resolves a user-typed book name (any case, any whitespace, common abbrev.)
    /// to a canonical name. Returns nil for anything we don't recognize so the
    /// editor can surface a clean "unknown book" message.
    static func canonical(for input: String) -> String? {
        let key = normalize(input)
        return aliases[key]
    }

    // MARK: - Internals

    /// Normalizes input: trim, lowercase, collapse internal whitespace to one
    /// space, and *also* support a no-space variant ("1cor") by stripping all
    /// whitespace as a fallback lookup. (`1cor` is handled by also indexing the
    /// no-space form of every alias below.)
    private static func normalize(_ input: String) -> String {
        let collapsed = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed
    }

    /// Lowercased alias → canonical name. Indexed at type init so lookups are O(1).
    /// The set is intentionally generous: full name, dotted abbreviation,
    /// undotted abbreviation, and a no-whitespace form for digit-prefixed books.
    private static let aliases: [String: String] = {
        var map: [String: String] = [:]

        func add(_ canonical: String, _ extras: [String] = []) {
            // Always allow the canonical form itself, lower- and no-space variants.
            register(canonical, as: canonical, in: &map)
            for alias in extras { register(alias, as: canonical, in: &map) }
        }

        // OT
        add("Genesis", ["gen", "ge", "gn"])
        add("Exodus", ["exo", "ex", "exod"])
        add("Leviticus", ["lev", "lv"])
        add("Numbers", ["num", "nm", "nu", "numb"])
        add("Deuteronomy", ["deut", "dt", "de"])
        add("Joshua", ["josh", "jos", "jsh"])
        add("Judges", ["judg", "jdg", "jgs"])
        add("Ruth", ["rth", "ru"])
        add("1 Samuel", ["1 sam", "1sam", "1 sm", "1sm", "i sam", "1samuel", "1 sa"])
        add("2 Samuel", ["2 sam", "2sam", "2 sm", "2sm", "ii sam", "2samuel", "2 sa"])
        add("1 Kings", ["1 kgs", "1kgs", "1 ki", "1ki", "1kings"])
        add("2 Kings", ["2 kgs", "2kgs", "2 ki", "2ki", "2kings"])
        add("1 Chronicles", ["1 chron", "1chron", "1 chr", "1chr", "1 ch", "1ch"])
        add("2 Chronicles", ["2 chron", "2chron", "2 chr", "2chr", "2 ch", "2ch"])
        add("Ezra", ["ezr"])
        add("Nehemiah", ["neh", "ne"])
        add("Esther", ["esth", "est"])
        add("Job", ["jb"])
        add("Psalms", ["psalm", "ps", "psa", "psm", "pss"])
        add("Proverbs", ["prov", "pr", "prv"])
        add("Ecclesiastes", ["eccl", "ec", "qoh"])
        add("Song of Solomon", ["song", "sos", "sng", "canticles", "song of songs"])
        add("Isaiah", ["isa", "is"])
        add("Jeremiah", ["jer", "jr"])
        add("Lamentations", ["lam", "la"])
        add("Ezekiel", ["ezek", "eze", "ezk"])
        add("Daniel", ["dan", "dn", "da"])
        add("Hosea", ["hos", "ho"])
        add("Joel", ["jl"])
        add("Amos", ["am", "amo"])
        add("Obadiah", ["obad", "ob"])
        add("Jonah", ["jon", "jnh"])
        add("Micah", ["mic", "mi"])
        add("Nahum", ["nah", "na"])
        add("Habakkuk", ["hab", "hb"])
        add("Zephaniah", ["zeph", "zep"])
        add("Haggai", ["hag", "hg"])
        add("Zechariah", ["zech", "zec", "zc"])
        add("Malachi", ["mal", "ml"])

        // NT
        add("Matthew", ["matt", "mt"])
        add("Mark", ["mk", "mrk"])
        add("Luke", ["lk", "luk"])
        add("John", ["jn", "joh", "jhn"])
        add("Acts", ["act"])
        add("Romans", ["rom", "ro", "rm"])
        add("1 Corinthians", ["1 cor", "1cor", "1 co", "1co"])
        add("2 Corinthians", ["2 cor", "2cor", "2 co", "2co"])
        add("Galatians", ["gal", "ga"])
        add("Ephesians", ["eph"])
        add("Philippians", ["phil", "php", "pp"])
        add("Colossians", ["col"])
        add("1 Thessalonians", ["1 thess", "1thess", "1 thes", "1thes", "1 th", "1th"])
        add("2 Thessalonians", ["2 thess", "2thess", "2 thes", "2thes", "2 th", "2th"])
        add("1 Timothy", ["1 tim", "1tim", "1 ti", "1ti"])
        add("2 Timothy", ["2 tim", "2tim", "2 ti", "2ti"])
        add("Titus", ["tit"])
        add("Philemon", ["phlm", "phm", "philem"])
        add("Hebrews", ["heb"])
        add("James", ["jas", "jm"])
        add("1 Peter", ["1 pet", "1pet", "1 pt", "1pt"])
        add("2 Peter", ["2 pet", "2pet", "2 pt", "2pt"])
        add("1 John", ["1 jn", "1jn", "1 jhn", "1jhn", "1 jo", "1jo"])
        add("2 John", ["2 jn", "2jn", "2 jhn", "2jhn"])
        add("3 John", ["3 jn", "3jn", "3 jhn", "3jhn"])
        add("Jude", ["jud"])
        add("Revelation", ["rev", "re", "rv", "apoc", "apocalypse"])

        return map
    }()

    /// Adds the alias's lowercase, normalized-space, and no-whitespace forms so
    /// `1cor`, `1 cor`, and `1 Cor.` all resolve.
    private static func register(_ alias: String, as canonical: String,
                                 in map: inout [String: String]) {
        let lowered = alias.lowercased()
        let collapsed = lowered
            .components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            .joined(separator: " ")
        map[collapsed] = canonical
        let noSpace = collapsed.replacingOccurrences(of: " ", with: "")
        if noSpace != collapsed { map[noSpace] = canonical }
        // Also strip a trailing period from dotted abbreviations: "gen." -> "gen".
        if collapsed.hasSuffix(".") {
            map[String(collapsed.dropLast())] = canonical
        }
    }
}
