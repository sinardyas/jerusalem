import Foundation

/// An immutable, value-type snapshot of a slide's appearance. The renderer works
/// only on these — never on live SwiftData models — which decouples rendering from
/// persistence and is the basis for edit/live separation in later phases.
struct RenderableSlide: Equatable, Hashable, Sendable {
    var backgroundKind: SlideBackgroundKind = .color
    var backgroundColorHex: String
    var elements: [RenderableElement]
    /// Optional looping motion background. When set *and* `backgroundKind == .video`,
    /// the renderer leaves the slide background transparent so the video can show
    /// through behind the text.
    var backgroundVideo: VideoCue? = nil
    /// Optional static image background, drawn aspect-fill behind the text.
    /// Only consulted when `backgroundKind == .image`.
    var backgroundImageURL: URL? = nil
    /// Second color for a gradient background. Drawn linearly with
    /// ``backgroundColorHex`` as the start stop along ``gradientAngle``.
    var gradientHex2: String? = nil
    var gradientAngle: Double = 135
}

/// A value-type snapshot of one slide element. Frame is normalized (0...1),
/// top-left origin, so it scales to any output resolution.
struct RenderableElement: Equatable, Hashable, Sendable {
    var kind: SlideElementKind
    var text: String?
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var fontName: String
    var fontSize: Double
    var colorHex: String
    var alignment: TextAlignmentOption
    var isBold: Bool
    var isItalic: Bool
    var isUnderlined: Bool = false
    var hasShadow: Bool
    var hasStroke: Bool
    var autoFit: Bool
    var imageFilename: String?

    // Phase 8.4 shape content — mirrors ``SlideElement``. Defaults keep existing
    // text/image snapshots and `Equatable`/`Hashable` synthesis valid.
    var shapeType: ShapeType = .rectangle
    var fillColorHex: String = "#3B82F6"
    var cornerRadius: Double = 0

    // Phase 8.3.1 typography depth — mirrors ``SlideElement``.
    var lineSpacingMultiplier: Double = 1.35
    var letterSpacing: Double = 0
    var strokeWidth: Double = 3.0
    var strokeColorHex: String = "#000000"
    var shadowBlur: Double = 12
    var shadowOffsetY: Double = -4
    var shadowColorHex: String = "#000000B3"
}

extension RenderableSlide {
    /// Snapshots a SwiftData ``Slide``. Must be called on the actor that owns the
    /// model (the main actor for the app's main context).
    init(_ slide: Slide) {
        var motionBackground: VideoCue?
        if slide.backgroundKind == .video,
           let filename = slide.backgroundVideoFilename,
           MediaImport.kind(forExtension: (filename as NSString).pathExtension) == .video {
            motionBackground = VideoCue(url: MediaStorage.url(forFilename: filename),
                                        loops: true, muted: true, endBehavior: .hold)
        }
        var imageBackground: URL?
        if slide.backgroundKind == .image,
           let filename = slide.backgroundImageFilename,
           MediaImport.kind(forExtension: (filename as NSString).pathExtension) == .image {
            imageBackground = MediaStorage.url(forFilename: filename)
        }
        self.init(
            backgroundKind: slide.backgroundKind,
            backgroundColorHex: slide.backgroundColorHex,
            elements: slide.orderedElements.map(RenderableElement.init),
            backgroundVideo: motionBackground,
            backgroundImageURL: imageBackground,
            gradientHex2: slide.gradientHex2,
            gradientAngle: slide.gradientAngle)
    }
}

extension RenderableElement {
    init(_ element: SlideElement) {
        self.init(
            kind: element.kind,
            text: element.text,
            x: element.x, y: element.y, width: element.width, height: element.height,
            fontName: element.fontName,
            fontSize: element.fontSize,
            colorHex: element.colorHex,
            alignment: element.alignment,
            isBold: element.isBold,
            isItalic: element.isItalic,
            isUnderlined: element.isUnderlined,
            hasShadow: element.hasShadow,
            hasStroke: element.hasStroke,
            autoFit: element.autoFit,
            imageFilename: element.imageFilename,
            shapeType: element.shapeType,
            fillColorHex: element.fillColorHex,
            cornerRadius: element.cornerRadius,
            lineSpacingMultiplier: element.lineSpacingMultiplier,
            letterSpacing: element.letterSpacing,
            strokeWidth: element.strokeWidth,
            strokeColorHex: element.strokeColorHex,
            shadowBlur: element.shadowBlur,
            shadowOffsetY: element.shadowOffsetY,
            shadowColorHex: element.shadowColorHex)
    }
}
