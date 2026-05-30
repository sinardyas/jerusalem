import Foundation
import SwiftData

enum SlideElementKind: String, Codable, Hashable, Sendable { case text, image, shape }
enum TextAlignmentOption: String, Codable, Hashable, Sendable {
    case leading, center, trailing, justified
}
/// Vector shape primitives. Drawn by ``SlideRenderer`` beneath images and text.
enum ShapeType: String, Codable, Hashable, Sendable {
    case rectangle, ellipse, roundedRectangle
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

    // Shape content (Phase 8.4). A vector primitive filled with `fillColorHex`,
    // optionally bordered via the existing `hasStroke`/`strokeWidth`/`strokeColorHex`
    // fields. `cornerRadius` is in points at the 1920×1080 reference (like `fontSize`)
    // and only applies to `.roundedRectangle`. Defaults keep existing rows unchanged.
    private var shapeTypeRaw: String = ShapeType.rectangle.rawValue
    var fillColorHex: String = "#3B82F6"
    var cornerRadius: Double = 0

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

    var shapeType: ShapeType {
        get { ShapeType(rawValue: shapeTypeRaw) ?? .rectangle }
        set { shapeTypeRaw = newValue.rawValue }
    }

    /// A short human label for this element in the editor's Layers panel.
    var layerName: String {
        switch kind {
        case .text:
            let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Text" : String(trimmed.prefix(32))
        case .image:
            return imageFilename ?? "Image"
        case .shape:
            switch shapeType {
            case .rectangle:        return "Rectangle"
            case .ellipse:          return "Ellipse"
            case .roundedRectangle: return "Rounded Rectangle"
            }
        }
    }
}
