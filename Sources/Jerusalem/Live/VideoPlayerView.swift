import SwiftUI
import AVFoundation

/// Hosts AVFoundation video playback for the output — hardware-decoded via
/// `AVPlayerLayer`, letterboxed (the output's black shows through). Looping uses
/// `AVQueuePlayer` + `AVPlayerLooper`. Falls back to nothing (black) if the file is
/// missing or unplayable — it must never crash the live output.
struct VideoPlayerView: NSViewRepresentable {
    let cue: VideoCue
    var onEnded: () -> Void = {}

    func makeNSView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.onEnded = onEnded
        view.apply(cue)
        return view
    }

    func updateNSView(_ view: PlayerContainerView, context: Context) {
        view.onEnded = onEnded
        view.apply(cue)
    }

    static func dismantleNSView(_ view: PlayerContainerView, coordinator: ()) {
        view.teardown()
    }
}

/// Layer-backed host for an `AVPlayerLayer`.
final class PlayerContainerView: NSView {
    private let playerLayer = AVPlayerLayer()
    private var player: AVPlayer?
    private var looper: AVPlayerLooper?
    private var endObserver: NSObjectProtocol?
    private var currentCue: VideoCue?
    var onEnded: () -> Void = {}

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Set the hosting layer before enabling wantsLayer (Apple's documented order
        // for a layer-hosting view) so the AVPlayerLayer displays reliably.
        layer = CALayer()
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }

    /// Sets up playback for `cue`, reusing the current player if it's unchanged.
    func apply(_ cue: VideoCue) {
        guard cue != currentCue else { return }
        teardown()
        currentCue = cue
        playerLayer.isHidden = false

        // Graceful fallback: a missing file shows black rather than crashing.
        guard FileManager.default.fileExists(atPath: cue.url.path) else { return }

        let item = AVPlayerItem(asset: VideoPrewarmer.shared.asset(for: cue.url))
        let activePlayer: AVPlayer
        if cue.loops {
            let queue = AVQueuePlayer()
            looper = AVPlayerLooper(player: queue, templateItem: item)
            activePlayer = queue
        } else {
            activePlayer = AVPlayer(playerItem: item)
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.handleEnd() }
            }
        }
        activePlayer.isMuted = cue.muted
        playerLayer.player = activePlayer
        player = activePlayer
        activePlayer.play()
    }

    private func handleEnd() {
        if currentCue?.endBehavior == .black { playerLayer.isHidden = true }
        onEnded()
    }

    func teardown() {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player?.pause()
        playerLayer.player = nil
        player = nil
        looper = nil
        currentCue = nil
    }
}
