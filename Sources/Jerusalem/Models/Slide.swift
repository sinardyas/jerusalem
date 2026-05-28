import Foundation
import SwiftData

/// What kind of background a slide draws behind its elements. Phase 8.3.2
/// expands the original "single color or optional image / video" implicit set
/// into an explicit four-way choice so the inspector can switch between them
/// without inferring intent from which `…Filename` happens to be set.
enum SlideBackgroundKind: String, Codable, Hashable, Sendable, CaseIterable {
    case color, gradient, image, video
}

/// One projected slide belonging to an ``Item``. Carries its background and the
/// ordered visual elements drawn on top. (Phase 2 renders these from the model;
/// richer background options arrive later.)
@Model
final class Slide {
    var order: Int = 0
    var sectionLabel: String?            // e.g. "Verse 1", "Chorus"
    private var backgroundKindRaw: String = SlideBackgroundKind.color.rawValue
    var backgroundColorHex: String = "#0F172A"
    var backgroundImageFilename: String? // optional static image background (under MediaStorage)
    var backgroundVideoFilename: String? // optional looping motion background (under MediaStorage)

    /// Phase 8.3.2 gradient backgrounds — second stop and the angle (in degrees,
    /// 0 = left→right, 90 = top→bottom). Only consulted when
    /// ``backgroundKind == .gradient``.
    var gradientHex2: String?
    var gradientAngle: Double = 135

    /// Phase 8: true once the user touched this slide in the WYSIWYG editor.
    /// ``ContentRebuilder`` then refuses to overwrite the item's slides, so edits
    /// survive a re-split of the lyrics block / Bible reference / sermon body.
    var isManuallyEdited: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \SlideElement.slide)
    var elements: [SlideElement] = []

    var item: Item?

    init(order: Int, sectionLabel: String? = nil, backgroundColorHex: String = "#0F172A") {
        self.order = order
        self.sectionLabel = sectionLabel
        self.backgroundColorHex = backgroundColorHex
    }

    var backgroundKind: SlideBackgroundKind {
        get { SlideBackgroundKind(rawValue: backgroundKindRaw) ?? .color }
        set { backgroundKindRaw = newValue.rawValue }
    }

    /// Elements in draw order (back to front).
    var orderedElements: [SlideElement] {
        elements.sorted { $0.order < $1.order }
    }
}
