import SwiftUI

/// Renders a value-snapshot ``RenderableSlide`` at the chosen aspect ratio,
/// re-rendering only when the content or pixel size changes. The shared display
/// primitive used by the slide grid, the inspector preview, and the live output.
struct RenderableSlideView: View {
    let renderable: RenderableSlide
    var aspectRatio: CGFloat = 16.0 / 9.0

    @Environment(\.displayScale) private var displayScale
    @State private var image: CGImage?

    var body: some View {
        GeometryReader { geo in
            let pixelSize = CGSize(width: max(1, geo.size.width * displayScale),
                                   height: max(1, geo.size.height * displayScale))
            Group {
                if let image {
                    Image(decorative: image, scale: displayScale).resizable()
                } else {
                    Color.black
                }
            }
            .task(id: RenderRequest(slide: renderable,
                                    width: Int(pixelSize.width),
                                    height: Int(pixelSize.height))) {
                image = SlideRenderer.makeImage(renderable, pixelSize: pixelSize)
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
    }
}

/// Convenience wrapper that snapshots a SwiftData ``Slide`` and renders it.
struct SlideView: View {
    let slide: Slide
    var aspectRatio: CGFloat = 16.0 / 9.0

    var body: some View {
        RenderableSlideView(renderable: RenderableSlide(slide), aspectRatio: aspectRatio)
    }
}

/// Composes a slide for display: a looping video behind the (transparent-backed)
/// text when the slide has a motion background, otherwise just the rendered slide.
/// Used wherever a live slide is shown (output + inspector).
struct SlideStageView: View {
    let renderable: RenderableSlide
    var aspectRatio: CGFloat = 16.0 / 9.0

    var body: some View {
        if let cue = renderable.backgroundVideo {
            ZStack {
                Color.black
                VideoPlayerView(cue: cue)
                RenderableSlideView(renderable: renderable)
            }
            .aspectRatio(aspectRatio, contentMode: .fit)
        } else {
            RenderableSlideView(renderable: renderable, aspectRatio: aspectRatio)
        }
    }
}

/// Identifies a unique render so `View.task` only re-renders on real changes.
private struct RenderRequest: Equatable {
    let slide: RenderableSlide
    let width: Int
    let height: Int
}
