import Foundation
import SwiftData

/// Seeds a sample song + playlist on first launch so the app opens with something
/// to look at during development. Runs only when the store is empty (idempotent).
///
/// Phase 6: authors the sample song as a lyrics block + ``SongSection`` rows and
/// lets ``ContentRebuilder`` derive the slides — same path the in-app editor uses.
enum SampleData {
    @MainActor
    static func seedIfNeeded(_ context: ModelContext) {
        let existing = (try? context.fetchCount(FetchDescriptor<Item>())) ?? 0
        guard existing == 0 else { return }

        let song = Item(kind: .song, title: "Amazing Grace", subtitle: "John Newton")
        song.theme = Theme.makeDefault()
        song.linesPerSlide = 2
        context.insert(song)

        let lyrics = """
        [Verse 1]
        Amazing grace! How sweet the sound
        That saved a wretch like me!
        I once was lost, but now am found;
        Was blind, but now I see.

        [Verse 2]
        ’Twas grace that taught my heart to fear,
        And grace my fears relieved;
        How precious did that grace appear
        The hour I first believed!

        [Chorus]
        My chains are gone, I’ve been set free
        My God, my Savior has ransomed me
        """
        ContentRebuilder.setLyrics(lyrics, on: song)

        let playlist = Playlist(name: "Sunday AM · May 31")
        let entry = PlaylistEntry(order: 0)
        entry.item = song
        playlist.entries = [entry]
        context.insert(playlist)

        try? context.save()
    }
}
