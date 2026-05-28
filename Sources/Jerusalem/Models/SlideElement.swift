import Foundation
import SwiftData

enum SlideElementKind: String, Codable, Hashable, Sendable { case text, image }
enum TextAlignmentOption: String, Codable, Hashable, Sendable {
    case leading, center, trailing, justified
}

/// A positioned element on a slide. For the MVP this is primarily styled text;
/// images reuse the same model with `imageFilename` set. The frame is stored in
/// normalized (0...1) coordinates so it scales to any output resolution.
@Model
final class SlideElement {
    var order: Int = 0
    private var kindRaw: String = SlideElementKind.text.rawValue

    // Normalized frame relative to the slide.
    var x: Double = 0.08
    var y: Double = 0.55
    var width: Double = 0.84
    var height: Double = 0.32

    // Text content + styling (font size is in points at a 1920×1080 reference).
    var text: String?
    var fontName: String = "Avenir Next"
    var fontSize: Double = 48
    var colorHex: String = "#FFFFFF"
    private var alignmentRaw: String = TextAlignmentOption.center.rawValue
    var isBold: Bool = true
    var isItalic: Bool = false
    var isUnderlined: Bool = false
    var hasShadow: Bool = true
    var hasStroke: Bool = false
    var autoFit: Bool = true

    // Phase 8.3.1 typography depth — line/letter spacing, stroke width + color,
    // shadow blur/offset/color. Defaults preserve Phase 1 visuals exactly so
    // existing slides don't shift on first load after the schema update.
    var lineSpacingMultiplier: Double = 1.35
    var letterSpacing: Double = 0
    var strokeWidth: Double = 3.0
    var strokeColorHex: String = "#000000"
    var shadowBlur: Double = 12
    var shadowOffsetY: Double = -4
    var shadowColorHex: String = "#000000B3"

    // Image content.
    var imageFilename: String?

    var slide: Slide?

    init(kind: SlideElementKind, order: Int = 0, text: String? = nil) {
        self.kindRaw = kind.rawValue
        self.order = order
        self.text = text
    }

    var kind: SlideElementKind {
        get { SlideElementKind(rawValue: kindRaw) ?? .text }
        set { kindRaw = newValue.rawValue }
    }

    var alignment: TextAlignmentOption {
        get { TextAlignmentOption(rawValue: alignmentRaw) ?? .center }
        set { alignmentRaw = newValue.rawValue }
    }
}
