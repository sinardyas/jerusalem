import Foundation
import SwiftData

/// The bridge from the *authored* representation (a lyrics block or a sermon
/// title+body) to the *projected* one (the ``Slide`` rows the renderer consumes).
///
/// Songs keep their ``SongSection`` rows as the source of truth; sermon/text items
/// keep their `bodyText`. Either way, calling ``rebuild(_:)`` regenerates the
/// item's slides + elements from those authored sources via ``SlideSplitter``,
/// applying the item's ``Theme`` (or ``Theme.makeDefault()``) so new content
/// looks acceptable without the Phase 8 editor.
///
/// This is the only path in the app that wholesale replaces an item's slides;
/// editing one slide directly (Phase 8) is a different code path.
@MainActor
enum ContentRebuilder {

    /// Rebuilds slides for an authored item from its source (song lyrics, sermon
    /// body, or Bible reference). No-op for media items, which have no derived
    /// slides.
    static func rebuild(_ item: Item) {
        switch item.kind {
        case .song:  rebuildSong(item)
        case .text:  rebuildText(item)
        case .bible: rebuildBible(item)
        case .media: return
        }
    }

    /// Replaces the item's lyrics block: re-parses, replaces ``SongSection`` rows,
    /// and rebuilds slides. Use this from the song editor.
    static func setLyrics(_ text: String, on item: Item) {
        let parsed = SongLyricsParser.parse(text)
        replaceSections(parsed, on: item)
        rebuildSong(item)
    }

    /// Replaces the sermon/text body and rebuilds slides.
    static func setBody(_ text: String, on item: Item) {
        item.bodyText = text
        rebuildText(item)
    }

    /// Updates a Bible item's reference + translation and rebuilds slides by
    /// looking the passage up in the bundled Bible store. Empty result (unknown
    /// reference or translation) clears the item's slides — the editor surfaces
    /// the unknown state visually.
    static func setBibleReference(_ reference: String, translation: String, on item: Item) {
        item.bibleReference = reference
        item.bibleTranslation = translation
        rebuildBible(item)
    }

    /// Discards any per-slide manual edits and re-derives the slides from the
    /// authored source. The content editors surface this when an item has
    /// `isManuallyEdited` slides, so the operator can recover from a bad edit
    /// without losing their lyrics block / sermon body / Bible reference.
    static func resetToAutoDerived(_ item: Item) {
        for slide in item.slides { slide.isManuallyEdited = false }
        rebuild(item)
    }

    /// True when at least one slide on `item` carries the manual-edit flag —
    /// i.e. the rebuilder is currently yielding to the editor's work. Editors
    /// use this to decide whether to surface the Reset button.
    static func hasManualEdits(_ item: Item) -> Bool {
        item.slides.contains(where: \.isManuallyEdited)
    }

    /// The canonical lyrics-block representation of a song's sections — what the
    /// editor's TextEditor should display when opening an existing song.
    static func lyricsText(for item: Item) -> String {
        let parsed = item.orderedSongSections.map {
            ParsedSongSection(kind: $0.kind, number: $0.number, lyrics: $0.lyrics)
        }
        return SongLyricsParser.format(parsed)
    }

    // MARK: - Songs

    private static func rebuildSong(_ item: Item) {
        let parsed = item.orderedSongSections.map {
            ParsedSongSection(kind: $0.kind, number: $0.number, lyrics: $0.lyrics)
        }
        let drafts = SlideSplitter.split(songSections: parsed, linesPerSlide: item.linesPerSlide)
        materialize(drafts, on: item)
    }

    private static func replaceSections(_ parsed: [ParsedSongSection], on item: Item) {
        // SwiftData cascades section deletion when we drop them from the array, but
        // the row also needs to be removed from the model context to actually delete.
        let context = item.modelContext
        for existing in item.songSections { context?.delete(existing) }
        item.songSections = parsed.enumerated().map { index, section in
            SongSection(kind: section.kind, number: section.number,
                        order: index, lyrics: section.lyrics)
        }
    }

    // MARK: - Bible

    private static func rebuildBible(_ item: Item) {
        guard let context = item.modelContext else { return }
        let translation = (item.bibleTranslation ?? "kjv").lowercased()
        // Reference missing or unparseable: clear slides so the editor surfaces
        // the empty state instead of stale content. The user's raw typed string
        // stays on the item so the editor field doesn't erase itself mid-edit.
        guard let referenceText = item.bibleReference,
              let reference = BibleReferenceParser.parse(referenceText)
        else {
            materialize([], on: item)
            return
        }
        let verses = BibleStore.verses(for: reference, translation: translation, in: context)
        let drafts = SlideSplitter.split(bibleVerses: verses, translation: translation)
        materialize(drafts, on: item)
        // Persist the canonical form so the editor reflects what we looked up
        // ("Psalm 23" → "Psalms 23").
        item.bibleReference = reference.displayText
    }

    // MARK: - Sermon / text

    private static func rebuildText(_ item: Item) {
        let drafts = SlideSplitter.split(
            sermonTitle: item.title,
            body: item.bodyText ?? "",
            linesPerSlide: item.linesPerSlide)
        materialize(drafts, on: item)
    }

    // MARK: - Slide materialization

    /// Replaces the item's slides with freshly built ones from `drafts`, themed.
    /// Once any slide on the item has `isManuallyEdited = true`, this is a no-op —
    /// Phase 8 edits are sticky, so the rebuilder yields to the editor.
    private static func materialize(_ drafts: [SlideDraft], on item: Item) {
        if item.slides.contains(where: \.isManuallyEdited) { return }
        let theme = item.theme ?? Theme.makeDefault()
        if item.theme == nil { item.theme = theme }
        let context = item.modelContext
        for existing in item.slides { context?.delete(existing) }

        let slides: [Slide] = drafts.enumerated().map { index, draft in
            let slide = Slide(order: index, sectionLabel: draft.sectionLabel)
            theme.apply(to: slide)
            let element = SlideElement(kind: .text, order: 0, text: draft.text)
            theme.apply(to: element)
            slide.elements = [element]
            return slide
        }
        item.slides = slides
        item.updatedAt = .now
    }
}
