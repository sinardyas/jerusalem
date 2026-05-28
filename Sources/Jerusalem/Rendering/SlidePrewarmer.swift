import AppKit

/// Best-effort pre-rendering for the *next* live slide: rasterizes it at the
/// output's pixel size before it goes live so advancing is "instant" — the
/// audience output's `RenderableSlideView` finds a cached `CGImage` instead of
/// running the renderer at switch time.
///
/// Mirrors ``VideoPrewarmer`` (same @MainActor singleton + bounded LRU pattern)
/// so the same `LiveState.nextProgramSlide` change hooks drive both. Real-world
/// benefit must be confirmed on hardware; this is a structural win, not a
/// timing guarantee.
@MainActor
final class SlidePrewarmer {
    static let shared = SlidePrewarmer()

    private struct Key: Hashable {
        let slide: RenderableSlide
        let width: Int
        let height: Int
    }

    private var cache: [Key: CGImage] = [:]
    private var order: [Key] = []
    private let limit = 6   // covers a few thumbnails + live + next + a margin

    /// Cache hit lookup. Returns nil when the slide / size combination hasn't
    /// been rendered yet.
    func image(for slide: RenderableSlide, pixelSize: CGSize) -> CGImage? {
        cache[keyFor(slide, pixelSize: pixelSize)]
    }

    /// Renders + caches if not already cached. Returns the rendered image so
    /// the caller can use it immediately. No-op when `slide` is nil.
    @discardableResult
    func prewarm(_ slide: RenderableSlide?, pixelSize: CGSize) -> CGImage? {
        guard let slide else { return nil }
        let key = keyFor(slide, pixelSize: pixelSize)
        if let existing = cache[key] { return existing }
        guard let rendered = SlideRenderer.makeImage(slide, pixelSize: pixelSize) else { return nil }
        store(rendered, for: key)
        return rendered
    }

    /// Drops everything. Used by tests; the live app's bounded LRU normally
    /// makes this unnecessary.
    func clear() {
        cache.removeAll()
        order.removeAll()
    }

    var cachedCount: Int { cache.count }

    // MARK: - Internals

    private func keyFor(_ slide: RenderableSlide, pixelSize: CGSize) -> Key {
        Key(slide: slide,
            width: Int(pixelSize.width.rounded()),
            height: Int(pixelSize.height.rounded()))
    }

    private func store(_ image: CGImage, for key: Key) {
        cache[key] = image
        order.append(key)
        while order.count > limit {
            cache.removeValue(forKey: order.removeFirst())
        }
    }
}
