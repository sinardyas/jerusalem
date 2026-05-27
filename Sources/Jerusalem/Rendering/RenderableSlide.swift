import Foundation

/// An immutable, value-type snapshot of a slide's appearance. The renderer works
/// only on these — never on live SwiftData models — which decouples rendering from
/// persistence and is the basis for edit/live separation in later phases.
struct RenderableSlide: Equatable, Hashable, Sendable {
    var backgroundColorHex: String
    var elements: [RenderableElement]
    /// Optional looping motion background. When set, the renderer leaves the slide
    /// background transparent so the video can show through behind the text.
    var backgroundVideo: VideoCue? = nil
    /// Optional static image background, drawn aspect-fill behind the text.
    var backgroundImageURL: URL? = nil
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
    var hasShadow: Bool
    var hasStroke: Bool
    var autoFit: Bool
    var imageFilename: String?
}

extension RenderableSlide {
    /// Snapshots a SwiftData ``Slide``. Must be called on the actor that owns the
    /// model (the main actor for the app's main context).
    init(_ slide: Slide) {
        var motionBackground: VideoCue?
        if let filename = slide.backgroundVideoFilename,
           MediaImport.kind(forExtension: (filename as NSString).pathExtension) == .video {
            motionBackground = VideoCue(url: MediaStorage.url(forFilename: filename),
                                        loops: true, muted: true, endBehavior: .hold)
        }
        var imageBackground: URL?
        if motionBackground == nil, let filename = slide.backgroundImageFilename,
           MediaImport.kind(forExtension: (filename as NSString).pathExtension) == .image {
            imageBackground = MediaStorage.url(forFilename: filename)
        }
        self.init(
            backgroundColorHex: slide.backgroundColorHex,
            elements: slide.orderedElements.map(RenderableElement.init),
            backgroundVideo: motionBackground,
            backgroundImageURL: imageBackground)
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
            hasShadow: element.hasShadow,
            hasStroke: element.hasStroke,
            autoFit: element.autoFit,
            imageFilename: element.imageFilename)
    }
}
