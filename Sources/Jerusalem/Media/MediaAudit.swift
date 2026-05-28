import Foundation

/// Catches media-on-disk gaps before Sunday morning does. Each path the
/// renderer / video player consults is checked here so the slide grid can
/// surface a "missing file" badge — the renderer's own fallbacks (silent skip,
/// black for video) are safe but invisible, and an operator stress-testing on
/// Saturday should see the warning while there's still time to fix it.
///
/// Pure (no model/UI dependencies) — caseless `enum` namespace.
enum MediaAudit {

    /// `true` when the bundled / imported file exists and is readable.
    static func isPresent(filename: String?) -> Bool {
        guard let filename, !filename.isEmpty else { return false }
        let url = MediaStorage.url(forFilename: filename)
        return FileManager.default.isReadableFile(atPath: url.path)
    }

    /// Walks every file path a ``RenderableSlide`` carries (slide background
    /// image / video, element images) and returns those that don't resolve.
    /// Empty result = the slide is fully self-contained.
    static func missingFiles(in slide: RenderableSlide) -> [String] {
        var missing: [String] = []
        if let url = slide.backgroundImageURL,
           !FileManager.default.isReadableFile(atPath: url.path) {
            missing.append(url.lastPathComponent)
        }
        if let cue = slide.backgroundVideo,
           !FileManager.default.isReadableFile(atPath: cue.url.path) {
            missing.append(cue.url.lastPathComponent)
        }
        for element in slide.elements where element.kind == .image {
            if let filename = element.imageFilename, !isPresent(filename: filename) {
                missing.append(filename)
            }
        }
        return missing
    }

    /// Convenience for a ``VideoCue`` (the live program's video items).
    static func isPresent(_ cue: VideoCue) -> Bool {
        FileManager.default.isReadableFile(atPath: cue.url.path)
    }
}
