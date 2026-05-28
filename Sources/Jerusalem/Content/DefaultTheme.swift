import Foundation

/// The code-defined default visual style for new content. Phase 8 will add a real
/// theme library + WYSIWYG editing; until then, this is what makes a freshly
/// authored song or sermon slide look acceptable straight from the editor.
extension Theme {
    /// Builds a fresh "Default Dark" theme — dark navy background, white centered
    /// Avenir Next at 56pt — that scales with the renderer's 1920×1080 reference.
    static func makeDefault() -> Theme {
        let theme = Theme(name: "Default Dark")
        theme.backgroundColorHex = "#0F172A"
        theme.fontName = "Avenir Next"
        theme.fontSize = 56
        theme.textColorHex = "#FFFFFF"
        return theme
    }

    /// Applies the theme to a freshly created slide's background.
    func apply(to slide: Slide) {
        slide.backgroundColorHex = backgroundColorHex
    }

    /// Applies the theme to a freshly created text element. Geometry stays at the
    /// renderer's default centered-text frame; only typography is themed.
    func apply(to element: SlideElement) {
        element.fontName = fontName
        element.fontSize = fontSize
        element.colorHex = textColorHex
        element.alignment = alignment
        element.isBold = isBold
        element.isItalic = isItalic
        element.isUnderlined = isUnderlined
        element.hasShadow = hasShadow
        element.hasStroke = hasStroke
        element.autoFit = autoFit
        element.lineSpacingMultiplier = lineSpacingMultiplier
        element.letterSpacing = letterSpacing
        element.strokeWidth = strokeWidth
        element.strokeColorHex = strokeColorHex
        element.shadowBlur = shadowBlur
        element.shadowOffsetY = shadowOffsetY
        element.shadowColorHex = shadowColorHex
    }

    /// Captures the visual style of `element` (typography + effects) into this
    /// theme. Used by the inspector's "Set as default style for new slides"
    /// action so subsequent `Add Text` clicks inherit what the user just picked.
    func copy(from element: SlideElement) {
        fontName = element.fontName
        fontSize = element.fontSize
        textColorHex = element.colorHex
        alignment = element.alignment
        isBold = element.isBold
        isItalic = element.isItalic
        isUnderlined = element.isUnderlined
        hasShadow = element.hasShadow
        hasStroke = element.hasStroke
        autoFit = element.autoFit
        lineSpacingMultiplier = element.lineSpacingMultiplier
        letterSpacing = element.letterSpacing
        strokeWidth = element.strokeWidth
        strokeColorHex = element.strokeColorHex
        shadowBlur = element.shadowBlur
        shadowOffsetY = element.shadowOffsetY
        shadowColorHex = element.shadowColorHex
    }
}
