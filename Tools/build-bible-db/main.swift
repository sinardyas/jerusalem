#!/usr/bin/env swift
// Tools/build-bible-db/main.swift
//
// Converts one or more OSIS XML Bible exports into the JSON shape the Jerusalem
// app's `BibleSeeder` reads — so dropping in real KJV/WEB OSIS files becomes a
// one-shot command instead of a code change.
//
// Usage:
//
//   swift Tools/build-bible-db/main.swift \
//     kjv:"King James Version":/path/to/kjv.osis.xml \
//     web:"World English Bible":/path/to/web.osis.xml \
//     > Sources/Jerusalem/Resources/bible-starter.json
//
// Each argument is `id:displayName:path`. The output JSON replaces
// `bible-starter.json`; rebuild the app and the new corpus is bundled.
//
// What this handles:
//   • The wrapped form:  `<verse osisID="John.3.16">text</verse>`
//   • The milestone form: `<verse sID="John.3.16"/> text <verse eID="John.3.16"/>`
//   • Standard OSIS book IDs (the canonical SBL three-letter codes).
//   • Inline markup inside verses (notes, w-tags, etc.) — children are stripped
//     down to their text content; whitespace is collapsed.
//
// What it does *not* handle (yet):
//   • Apocrypha / deuterocanonical books — only the 66-book Protestant canon.
//   • Footnote / cross-reference inclusion — notes are dropped.
//   • Variant readings / `<choice>` blocks — first child wins.
//
// Foundation only — no package manifest, no external dependencies.

import Foundation

// MARK: - CLI parsing

struct Job {
    let id: String
    let displayName: String
    let url: URL
}

func parseArgs(_ raw: [String]) -> (jobs: [Job], errors: [String]) {
    var jobs: [Job] = []
    var errors: [String] = []
    for arg in raw {
        let parts = arg.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3 else {
            errors.append("Expected `id:displayName:path` — got `\(arg)`")
            continue
        }
        let id = String(parts[0]).lowercased()
        let displayName = String(parts[1])
        let url = URL(fileURLWithPath: String(parts[2]))
        guard FileManager.default.fileExists(atPath: url.path) else {
            errors.append("File not found: \(url.path)")
            continue
        }
        jobs.append(Job(id: id, displayName: displayName, url: url))
    }
    return (jobs, errors)
}

let argv = Array(CommandLine.arguments.dropFirst())
guard !argv.isEmpty else {
    FileHandle.standardError.write(Data("""
        usage: swift build-bible-db/main.swift id:displayName:path [...]

        Example:
          swift Tools/build-bible-db/main.swift \\
              kjv:"King James Version":./kjv.osis.xml \\
              web:"World English Bible":./web.osis.xml \\
              > Sources/Jerusalem/Resources/bible-starter.json

        """.utf8))
    exit(64)
}
let (jobs, argErrors) = parseArgs(argv)
if !argErrors.isEmpty {
    for error in argErrors { FileHandle.standardError.write(Data("error: \(error)\n".utf8)) }
    exit(64)
}

// MARK: - OSIS book ID → canonical Jerusalem book name

let osisBookMap: [String: String] = [
    // OT
    "Gen": "Genesis", "Exod": "Exodus", "Lev": "Leviticus", "Num": "Numbers",
    "Deut": "Deuteronomy", "Josh": "Joshua", "Judg": "Judges", "Ruth": "Ruth",
    "1Sam": "1 Samuel", "2Sam": "2 Samuel",
    "1Kgs": "1 Kings", "2Kgs": "2 Kings",
    "1Chr": "1 Chronicles", "2Chr": "2 Chronicles",
    "Ezra": "Ezra", "Neh": "Nehemiah", "Esth": "Esther",
    "Job": "Job", "Ps": "Psalms", "Prov": "Proverbs", "Eccl": "Ecclesiastes",
    "Song": "Song of Solomon",
    "Isa": "Isaiah", "Jer": "Jeremiah", "Lam": "Lamentations",
    "Ezek": "Ezekiel", "Dan": "Daniel",
    "Hos": "Hosea", "Joel": "Joel", "Amos": "Amos", "Obad": "Obadiah",
    "Jonah": "Jonah", "Mic": "Micah", "Nah": "Nahum", "Hab": "Habakkuk",
    "Zeph": "Zephaniah", "Hag": "Haggai", "Zech": "Zechariah", "Mal": "Malachi",
    // NT
    "Matt": "Matthew", "Mark": "Mark", "Luke": "Luke", "John": "John", "Acts": "Acts",
    "Rom": "Romans",
    "1Cor": "1 Corinthians", "2Cor": "2 Corinthians",
    "Gal": "Galatians", "Eph": "Ephesians", "Phil": "Philippians", "Col": "Colossians",
    "1Thess": "1 Thessalonians", "2Thess": "2 Thessalonians",
    "1Tim": "1 Timothy", "2Tim": "2 Timothy", "Titus": "Titus", "Phlm": "Philemon",
    "Heb": "Hebrews", "Jas": "James",
    "1Pet": "1 Peter", "2Pet": "2 Peter",
    "1John": "1 John", "2John": "2 John", "3John": "3 John",
    "Jude": "Jude", "Rev": "Revelation",
]

// MARK: - SAX parser for OSIS

struct Verse {
    let book: String
    let chapter: Int
    let number: Int
    var text: String
}

/// Walks the OSIS XML in one pass, collecting verses keyed by their osisID.
/// Handles both the milestone form (`<verse sID>` / `<verse eID>`) and the
/// wrapped form (`<verse osisID="...">...</verse>`).
final class OSISReader: NSObject, XMLParserDelegate {
    var verses: [Verse] = []
    var skipped: [String] = []

    private var openVerse: (book: String, chapter: Int, number: Int)?
    private var openText: String = ""
    // Suppress note/reference content from showing up inside verse text.
    private var suppressDepth = 0

    func parse(url: URL) throws {
        let data = try Data(contentsOf: url)
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        if !parser.parse(), let error = parser.parserError {
            throw error
        }
        flushOpenVerse()
    }

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        switch element {
        case "verse":
            if let osisID = attributes["osisID"] ?? attributes["sID"] {
                flushOpenVerse()
                openVerse = decodeOSISID(osisID)
                openText = ""
            } else if attributes["eID"] != nil {
                flushOpenVerse()
            }
        case "note", "reference", "rdg":
            suppressDepth += 1
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?,
                qualifiedName: String?) {
        switch element {
        case "verse":
            // Wrapped form: the close-tag is the natural flush point.
            flushOpenVerse()
        case "note", "reference", "rdg":
            suppressDepth = max(0, suppressDepth - 1)
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard openVerse != nil, suppressDepth == 0 else { return }
        openText.append(string)
    }

    private func flushOpenVerse() {
        guard let open = openVerse else { return }
        let cleaned = openText
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !cleaned.isEmpty {
            verses.append(Verse(book: open.book, chapter: open.chapter, number: open.number, text: cleaned))
        }
        openVerse = nil
        openText = ""
    }

    /// Decodes `Gen.1.1`, `1Cor.13.4`, etc. Maps the OSIS book ID to the
    /// canonical Jerusalem book name; unknown books are skipped (logged for the
    /// user to know we dropped them).
    private func decodeOSISID(_ raw: String) -> (book: String, chapter: Int, number: Int)? {
        // Some OSIS files emit verse spans like `Gen.1.1 Gen.1.2` — take the first.
        let first = raw.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? raw
        let parts = first.split(separator: ".").map(String.init)
        guard parts.count >= 3,
              let chapter = Int(parts[1]),
              let number = Int(parts[2])
        else { return nil }
        guard let book = osisBookMap[parts[0]] else {
            if !skipped.contains(parts[0]) { skipped.append(parts[0]) }
            return nil
        }
        return (book, chapter, number)
    }
}

// MARK: - Run

struct OutputTranslation: Encodable {
    let id: String
    let displayName: String
    let verses: [OutputVerse]
}
struct OutputVerse: Encodable {
    let book: String
    let chapter: Int
    let number: Int
    let text: String
}
struct OutputRoot: Encodable {
    let version: Int
    let note: String
    let translations: [OutputTranslation]
}

var translations: [OutputTranslation] = []
for job in jobs {
    let reader = OSISReader()
    do {
        try reader.parse(url: job.url)
    } catch {
        FileHandle.standardError.write(Data("parse error in \(job.url.lastPathComponent): \(error)\n".utf8))
        exit(70)
    }
    if !reader.skipped.isEmpty {
        let list = reader.skipped.joined(separator: ", ")
        FileHandle.standardError.write(Data("note: skipped non-Protestant-canon books in \(job.id): \(list)\n".utf8))
    }
    FileHandle.standardError.write(Data("\(job.id): \(reader.verses.count) verses\n".utf8))
    translations.append(OutputTranslation(
        id: job.id,
        displayName: job.displayName,
        verses: reader.verses.map { OutputVerse(book: $0.book, chapter: $0.chapter, number: $0.number, text: $0.text) }))
}

let root = OutputRoot(
    version: 1,
    note: "Built by Tools/build-bible-db from OSIS XML on \(ISO8601DateFormatter().string(from: .now)).",
    translations: translations)

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
let data = try encoder.encode(root)
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data("\n".utf8))
