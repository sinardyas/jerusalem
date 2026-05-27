import SwiftUI

/// The full-bleed audience output. Renders whatever ``LiveState`` resolves to,
/// letterboxed on black, with an optional fade between changes.
struct OutputView: View {
    var live: LiveState

    var body: some View {
        ZStack {
            Color.black
            content
                .id(live.content)
                .transition(.opacity)
        }
        .ignoresSafeArea()
        .animation(live.transition == .fade ? .easeInOut(duration: 0.3) : nil,
                   value: live.content)
    }

    @ViewBuilder private var content: some View {
        switch live.content {
        case .empty, .black:
            Color.clear
        case .logo:
            LogoView()
        case .slide(let renderable):
            SlideStageView(renderable: renderable)
        case .video(let cue):
            VideoPlayerView(cue: cue, onEnded: {
                if cue.endBehavior == .advance { live.next() }
            })
        }
    }
}

/// Placeholder holding-slide shown by the Logo panic key. A user-configurable logo
/// image is a later phase.
struct LogoView: View {
    var body: some View {
        Text("Jerusalem")
            .font(.system(size: 64, weight: .light, design: .serif))
            .foregroundStyle(.white.opacity(0.85))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
