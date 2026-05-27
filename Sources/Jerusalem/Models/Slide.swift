import Foundation
import SwiftData

/// One projected slide belonging to an ``Item``. Carries its background and the
/// ordered visual elements drawn on top. (Phase 2 renders these from the model;
/// richer background options arrive later.)
@Model
final class Slide {
    var order: Int = 0
    var sectionLabel: String?            // e.g. "Verse 1", "Chorus"
    var backgroundColorHex: String = "#0F172A"
    var backgroundImageFilename: String? // optional static image background (under MediaStorage)
    var backgroundVideoFilename: String? // optional looping motion background (under MediaStorage)

    @Relationship(deleteRule: .cascade, inverse: \SlideElement.slide)
    var elements: [SlideElement] = []

    var item: Item?

    init(order: Int, sectionLabel: String? = nil, backgroundColorHex: String = "#0F172A") {
        self.order = order
        self.sectionLabel = sectionLabel
        self.backgroundColorHex = backgroundColorHex
    }

    /// Elements in draw order (back to front).
    var orderedElements: [SlideElement] {
        elements.sorted { $0.order < $1.order }
    }
}
