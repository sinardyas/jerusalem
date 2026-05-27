import Foundation
import SwiftData

/// Seeds a sample song + playlist on first launch so the app opens with something
/// to look at during development. Runs only when the store is empty (idempotent).
enum SampleData {
    static func seedIfNeeded(_ context: ModelContext) {
        let existing = (try? context.fetchCount(FetchDescriptor<Item>())) ?? 0
        guard existing == 0 else { return }

        let song = Item(kind: .song, title: "Amazing Grace", subtitle: "John Newton")
        song.theme = Theme(name: "Default Dark")

        let verses: [(label: String, text: String)] = [
            ("Verse 1", "Amazing grace! How sweet the sound\nThat saved a wretch like me!"),
            ("Verse 1", "I once was lost, but now am found;\nWas blind, but now I see."),
            ("Verse 2", "’Twas grace that taught my heart to fear,\nAnd grace my fears relieved;"),
            ("Chorus",  "My chains are gone, I’ve been set free\nMy God, my Savior has ransomed me"),
        ]
        for (index, verse) in verses.enumerated() {
            let slide = Slide(order: index, sectionLabel: verse.label)
            slide.elements = [SlideElement(kind: .text, text: verse.text)]
            song.slides.append(slide)
        }
        context.insert(song)

        let playlist = Playlist(name: "Sunday AM · May 31")
        let entry = PlaylistEntry(order: 0)
        entry.item = song
        playlist.entries = [entry]
        context.insert(playlist)

        try? context.save()
    }
}
