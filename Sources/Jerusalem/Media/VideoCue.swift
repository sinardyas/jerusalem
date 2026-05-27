import Foundation

/// What happens when a non-looping clip reaches its end.
enum VideoEndBehavior: String, Codable, CaseIterable, Identifiable, Sendable, Hashable {
    case hold, black, advance
    var id: String { rawValue }
    var label: String {
        switch self {
        case .hold:    "Hold last frame"
        case .black:   "Go to black"
        case .advance: "Advance to next"
        }
    }
}

/// An immutable description of a video to play on the output. A value type, so it
/// can live inside ``LiveState``'s snapshot content (edit/live separation).
struct VideoCue: Equatable, Hashable, Sendable {
    var url: URL
    var loops: Bool
    var muted: Bool
    var endBehavior: VideoEndBehavior
}
