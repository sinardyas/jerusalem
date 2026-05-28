import Foundation
import SwiftData

/// A reusable visual style applied to slides. The MVP ships one default theme;
/// a full theme library is a later phase.
@Model
final class Theme {
    var uuid: UUID = UUID()
    var name: String = "Default Dark"
    var backgroundColorHex: String = "#0F172A"
    var fontName: String = "Avenir Next"
    var fontSize: Double = 48
    var textColorHex: String = "#FFFFFF"

    // Phase 8.3.3 — element styling captured from "Set as default style for
    // new slides". Defaults match what `Theme.apply(to:)` already produces so
    // existing themes stay visually identical until the user updates them.
    var alignmentRaw: String = "center"
    var isBold: Bool = true
    var isItalic: Bool = false
    var isUnderlined: Bool = false
    var hasShadow: Bool = true
    var hasStroke: Bool = false
    var autoFit: Bool = true
    var lineSpacingMultiplier: Double = 1.35
    var letterSpacing: Double = 0
    var strokeWidth: Double = 3.0
    var strokeColorHex: String = "#000000"
    var shadowBlur: Double = 12
    var shadowOffsetY: Double = -4
    var shadowColorHex: String = "#000000B3"

    init(name: String = "Default Dark") {
        self.name = name
    }

    var alignment: TextAlignmentOption {
        get { TextAlignmentOption(rawValue: alignmentRaw) ?? .center }
        set { alignmentRaw = newValue.rawValue }
    }
}
