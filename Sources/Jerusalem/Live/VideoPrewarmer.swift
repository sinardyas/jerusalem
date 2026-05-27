import AVFoundation

/// Best-effort pre-buffering for the *next* clip: preloads its asset so playback
/// starts quickly when it goes live. Caches `AVURLAsset`s by URL (bounded).
///
/// This reduces start latency; it isn't a guarantee of instant start — the real
/// effect must be measured on hardware.
@MainActor
final class VideoPrewarmer {
    static let shared = VideoPrewarmer()

    private var assets: [URL: AVURLAsset] = [:]
    private var order: [URL] = []
    private let limit = 4

    /// Returns a cached asset for `url`, creating and kicking off an async load on
    /// first use. The same instance is reused so the live player benefits from any
    /// buffering already done.
    func asset(for url: URL) -> AVURLAsset {
        if let existing = assets[url] { return existing }
        let asset = AVURLAsset(url: url)
        store(asset, for: url)
        Task { _ = try? await asset.load(.isPlayable, .duration) }
        return asset
    }

    /// Warms the next clip (non-looping clips only — a loop starts once and stays).
    func prewarm(_ cue: VideoCue?) {
        guard let cue, !cue.loops, FileManager.default.fileExists(atPath: cue.url.path) else { return }
        _ = asset(for: cue.url)
    }

    private func store(_ asset: AVURLAsset, for url: URL) {
        assets[url] = asset
        order.append(url)
        while order.count > limit {
            assets[order.removeFirst()] = nil
        }
    }
}
