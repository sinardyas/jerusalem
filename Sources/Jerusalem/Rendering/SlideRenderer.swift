import AppKit

/// The single source of truth for *what a slide looks like*. Renders a
/// ``RenderableSlide`` into a `CGImage` using AppKit text drawing (TextKit /
/// Core Text), with stroke, shadow, alignment, line spacing, and auto-fit.
///
/// One rendering path feeds slide-grid thumbnails, the inspector preview, and
/// (from Phase 3) the live audience output. Rendering must happen on the main
/// thread (AppKit text drawing); the app drives it from `View.task`.
enum SlideRenderer {

    /// Reference height for normalized layout and font sizing (matches 1920×1080).
    static let referenceHeight: CGFloat = 1080

    /// Renders a slide into an RGBA `CGImage` of the given pixel size.
    static func makeImage(_ slide: RenderableSlide, pixelSize: CGSize) -> CGImage? {
        let width = max(1, Int(pixelSize.width.rounded()))
        let height = max(1, Int(pixelSize.height.rounded()))

        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        let size = CGSize(width: width, height: height)

        // Base fill — skipped for a motion (video) background so the video shows
        // through; black under a static image background so any letterboxing is black.
        if slide.backgroundVideo == nil {
            let base = slide.backgroundImageURL != nil
                ? NSColor.black
                : (NSColor(hex: slide.backgroundColorHex) ?? .black)
            context.setFillColor(base.cgColor)
            context.fill(CGRect(origin: .zero, size: size))
        }

        // Flip to a top-left origin so normalized (top-left) coordinates and AppKit
        // text drawing line up.
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)

        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        defer { NSGraphicsContext.restoreGraphicsState() }

        // Static image background (aspect-fill), if present and loadable.
        if slide.backgroundVideo == nil,
           let url = slide.backgroundImageURL,
           let image = NSImage(contentsOf: url) {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: CGRect(origin: .zero, size: size)).addClip()
            image.draw(in: aspectFill(imageSize: image.size, in: CGRect(origin: .zero, size: size)))
            NSGraphicsContext.restoreGraphicsState()
        }

        let scale = size.height / referenceHeight
        for element in slide.elements where element.kind == .text {
            draw(element, in: size, scale: scale)
        }

        return context.makeImage()
    }

    /// Returns the largest font size (≤ `baseSize`) at which `text` fits the box
    /// height when wrapped to the box width. Exposed for testing the auto-fit rule.
    static func fittedFontSize(
        text: String, fontName: String, isBold: Bool, isItalic: Bool,
        baseSize: CGFloat, boxSize: CGSize
    ) -> CGFloat {
        let minSize = max(8, baseSize * 0.25)
        var fontSize = baseSize
        for _ in 0..<16 {
            let attributed = measuringString(text, fontName: fontName,
                                             isBold: isBold, isItalic: isItalic, fontSize: fontSize)
            let fitted = attributed.boundingRect(
                with: CGSize(width: boxSize.width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading])
            if fitted.height <= boxSize.height || fontSize <= minSize { break }
            let ratio = boxSize.height / fitted.height
            fontSize = max(minSize, fontSize * min(0.95, max(0.6, ratio)))
        }
        return fontSize
    }

    // MARK: - Private

    /// Rect that scales `imageSize` to cover `bounds` while preserving aspect ratio.
    private static func aspectFill(imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return bounds }
        let scale = max(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let scaled = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: bounds.midX - scaled.width / 2, y: bounds.midY - scaled.height / 2,
                      width: scaled.width, height: scaled.height)
    }

    private static func draw(_ element: RenderableElement, in size: CGSize, scale: CGFloat) {
        guard let text = element.text, !text.isEmpty else { return }

        let box = CGRect(x: element.x * size.width, y: element.y * size.height,
                         width: element.width * size.width, height: element.height * size.height)
        let baseSize = element.fontSize * scale
        let fontSize = element.autoFit
            ? fittedFontSize(text: text, fontName: element.fontName,
                             isBold: element.isBold, isItalic: element.isItalic,
                             baseSize: baseSize, boxSize: box.size)
            : baseSize

        let attributed = styledString(text, element: element, fontSize: fontSize)

        // Vertically center the text block within the element box.
        let measured = attributed.boundingRect(
            with: CGSize(width: box.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]).height
        let textHeight = min(box.height, ceil(measured))
        let drawRect = CGRect(x: box.minX, y: box.minY + (box.height - textHeight) / 2,
                              width: box.width, height: textHeight)

        attributed.draw(with: drawRect, options: [.usesLineFragmentOrigin], context: nil)
    }

    private static func font(_ name: String, size: CGFloat, isBold: Bool, isItalic: Bool) -> NSFont {
        var font = NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size)
        var traits: NSFontDescriptor.SymbolicTraits = []
        if isBold { traits.insert(.bold) }
        if isItalic { traits.insert(.italic) }
        if !traits.isEmpty {
            let descriptor = font.fontDescriptor.withSymbolicTraits(traits)
            if let adjusted = NSFont(descriptor: descriptor, size: size) { font = adjusted }
        }
        return font
    }

    private static func paragraph(_ alignment: TextAlignmentOption, fontSize: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        switch alignment {
        case .leading:  style.alignment = .left
        case .center:   style.alignment = .center
        case .trailing: style.alignment = .right
        }
        style.lineSpacing = fontSize * 0.06
        return style
    }

    /// Minimal attributes for measurement (color/stroke/shadow don't affect layout).
    private static func measuringString(
        _ text: String, fontName: String, isBold: Bool, isItalic: Bool, fontSize: CGFloat
    ) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: font(fontName, size: fontSize, isBold: isBold, isItalic: isItalic),
            .paragraphStyle: paragraph(.center, fontSize: fontSize),
        ])
    }

    /// Full styled attributes for drawing.
    private static func styledString(
        _ text: String, element: RenderableElement, fontSize: CGFloat
    ) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font(element.fontName, size: fontSize, isBold: element.isBold, isItalic: element.isItalic),
            .foregroundColor: NSColor(hex: element.colorHex) ?? .white,
            .paragraphStyle: paragraph(element.alignment, fontSize: fontSize),
        ]
        if element.hasStroke {
            attributes[.strokeColor] = NSColor.black
            attributes[.strokeWidth] = -3.0   // negative = fill *and* stroke
        }
        if element.hasShadow {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.7)
            shadow.shadowOffset = NSSize(width: 0, height: -max(1, fontSize * 0.05))
            shadow.shadowBlurRadius = fontSize * 0.12
            attributes[.shadow] = shadow
        }
        return NSAttributedString(string: text, attributes: attributes)
    }
}
