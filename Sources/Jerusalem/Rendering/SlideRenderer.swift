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
        switch slide.backgroundKind {
        case .video:
            // Transparent backdrop — composited under the live video.
            break
        case .image:
            // Black so letterboxing under an off-aspect image reads as theatre, not bleed.
            context.setFillColor(NSColor.black.cgColor)
            context.fill(CGRect(origin: .zero, size: size))
        case .color:
            let base = NSColor(hex: slide.backgroundColorHex) ?? .black
            context.setFillColor(base.cgColor)
            context.fill(CGRect(origin: .zero, size: size))
        case .gradient:
            drawGradient(slide: slide, in: context, size: size)
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
        if slide.backgroundKind == .image,
           let url = slide.backgroundImageURL,
           let image = NSImage(contentsOf: url) {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: CGRect(origin: .zero, size: size)).addClip()
            image.draw(in: aspectFill(imageSize: image.size, in: CGRect(origin: .zero, size: size)))
            NSGraphicsContext.restoreGraphicsState()
        }

        let scale = size.height / referenceHeight
        // Single ordered pass: elements are pre-sorted back→front by `order`
        // (see `Slide.orderedElements`), so the editor's Layers panel can restack
        // any object type above or below any other — there is no fixed
        // shape→image→text precedence.
        for element in slide.elements {
            switch element.kind {
            case .shape: drawShapeElement(element, in: size, scale: scale)
            case .image: drawImageElement(element, in: size)
            case .text:  draw(element, in: size, scale: scale)
            }
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

    /// Draws a two-stop linear gradient between ``backgroundColorHex`` and
    /// ``gradientHex2`` along ``gradientAngle`` (0° = left→right, 90° =
    /// top→bottom). Falls back to a solid fill if either stop is missing.
    private static func drawGradient(slide: RenderableSlide,
                                     in context: CGContext, size: CGSize) {
        let start = NSColor(hex: slide.backgroundColorHex) ?? .black
        let end = NSColor(hex: slide.gradientHex2 ?? slide.backgroundColorHex) ?? start
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [start.cgColor, end.cgColor] as CFArray,
            locations: [0.0, 1.0]) else {
            context.setFillColor(start.cgColor)
            context.fill(CGRect(origin: .zero, size: size))
            return
        }
        let radians = slide.gradientAngle * .pi / 180
        // A unit vector in the requested direction; the gradient covers the
        // bounding rectangle along that axis from one edge to the opposite.
        let dx = cos(radians), dy = sin(radians)
        let half = CGPoint(x: size.width / 2, y: size.height / 2)
        // Project the half-diagonal onto the direction vector so the gradient
        // fills corner-to-corner regardless of angle.
        let extent = abs(dx) * (size.width / 2) + abs(dy) * (size.height / 2)
        let startPoint = CGPoint(x: half.x - dx * extent, y: half.y - dy * extent)
        let endPoint = CGPoint(x: half.x + dx * extent, y: half.y + dy * extent)
        context.drawLinearGradient(gradient, start: startPoint, end: endPoint, options: [])
    }

    /// Rect that scales `imageSize` to cover `bounds` while preserving aspect ratio.
    private static func aspectFill(imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return bounds }
        let scale = max(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let scaled = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: bounds.midX - scaled.width / 2, y: bounds.midY - scaled.height / 2,
                      width: scaled.width, height: scaled.height)
    }

    /// Aspect-fills a per-element image into its normalized frame. Missing /
    /// unloadable files are a silent no-op so a deleted clip can never crash
    /// the renderer mid-service — the slide's other elements still draw.
    private static func drawImageElement(_ element: RenderableElement, in size: CGSize) {
        guard let filename = element.imageFilename else { return }
        let url = MediaStorage.url(forFilename: filename)
        guard let image = NSImage(contentsOf: url) else { return }
        let box = CGRect(x: element.x * size.width, y: element.y * size.height,
                         width: element.width * size.width, height: element.height * size.height)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: box).addClip()
        image.draw(in: aspectFill(imageSize: image.size, in: box))
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Fills a vector shape into its normalized frame, with an optional border
    /// reusing the element's stroke fields. Corner radius is authored at the
    /// reference height, so it scales with the output like `fontSize` does.
    private static func drawShapeElement(_ element: RenderableElement, in size: CGSize, scale: CGFloat) {
        let box = CGRect(x: element.x * size.width, y: element.y * size.height,
                         width: element.width * size.width, height: element.height * size.height)
        guard box.width > 0, box.height > 0 else { return }

        let path: NSBezierPath
        switch element.shapeType {
        case .rectangle:
            path = NSBezierPath(rect: box)
        case .ellipse:
            path = NSBezierPath(ovalIn: box)
        case .roundedRectangle:
            // Clamp the radius so it can't exceed half the smaller side.
            let radius = min(element.cornerRadius * scale, min(box.width, box.height) / 2)
            path = NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius)
        }

        NSGraphicsContext.saveGraphicsState()
        (NSColor(hex: element.fillColorHex) ?? .systemBlue).setFill()
        path.fill()
        if element.hasStroke {
            (NSColor(hex: element.strokeColorHex) ?? .black).setStroke()
            path.lineWidth = max(0.1, element.strokeWidth) * scale
            path.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
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
        var traits: NSFontDescriptor.SymbolicTraits = []
        if isBold { traits.insert(.bold) }
        if isItalic { traits.insert(.italic) }
        // The picker offers *family* names ("Avenir Next", "Helvetica Neue", …);
        // `NSFont(name:)` only accepts PostScript names and would return nil for
        // most of them (silently falling back to the system font), so resolve the
        // family through a descriptor and apply bold/italic as symbolic traits.
        let base = NSFontDescriptor(fontAttributes: [.family: name])
        let descriptor = traits.isEmpty ? base : base.withSymbolicTraits(traits)
        if let resolved = NSFont(descriptor: descriptor, size: size) { return resolved }
        // The family lacks the requested trait — use it without the trait.
        if let plain = NSFont(descriptor: base, size: size) { return plain }
        // Unknown family (e.g. the special "SF Pro Text") — system font + traits.
        var system = NSFont.systemFont(ofSize: size)
        if !traits.isEmpty,
           let adjusted = NSFont(descriptor: system.fontDescriptor.withSymbolicTraits(traits), size: size) {
            system = adjusted
        }
        return system
    }

    private static func paragraph(_ alignment: TextAlignmentOption, fontSize: CGFloat,
                                  lineSpacingMultiplier: Double = 1.35) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        switch alignment {
        case .leading:   style.alignment = .left
        case .center:    style.alignment = .center
        case .trailing:  style.alignment = .right
        case .justified: style.alignment = .justified
        }
        // A multiplier of 1.0 means "leading = font size" — `NSParagraphStyle.lineSpacing`
        // is *additional* leading, so subtract one before scaling by the font.
        style.lineSpacing = max(0, fontSize * (lineSpacingMultiplier - 1.0))
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
        let scale = fontSize / max(1, element.fontSize)
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font(element.fontName, size: fontSize, isBold: element.isBold, isItalic: element.isItalic),
            .foregroundColor: NSColor(hex: element.colorHex) ?? .white,
            .paragraphStyle: paragraph(element.alignment, fontSize: fontSize,
                                       lineSpacingMultiplier: element.lineSpacingMultiplier),
        ]
        if element.letterSpacing != 0 {
            // Letter-spacing is authored at the reference font size, so scale
            // it down for autofit's adjusted size — same visual weight either way.
            attributes[.kern] = element.letterSpacing * scale
        }
        if element.isUnderlined {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        if element.hasStroke {
            attributes[.strokeColor] = NSColor(hex: element.strokeColorHex) ?? .black
            // Negative width = fill *and* stroke. The number is a percent of the
            // font size in AppKit's API, so scaling is automatic.
            let normalized = max(0.1, element.strokeWidth)
            attributes[.strokeWidth] = -normalized
        }
        if element.hasShadow {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor(hex: element.shadowColorHex)
                ?? NSColor.black.withAlphaComponent(0.7)
            shadow.shadowOffset = NSSize(width: 0, height: element.shadowOffsetY * scale)
            shadow.shadowBlurRadius = max(0, element.shadowBlur * scale)
            attributes[.shadow] = shadow
        }
        return NSAttributedString(string: text, attributes: attributes)
    }
}
