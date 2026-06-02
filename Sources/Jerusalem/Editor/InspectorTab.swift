import Foundation

/// The three tabs of the re-skinned slide-editor inspector (Phase 8.11): the
/// selected object's styling (`format`), its position/size/layer order
/// (`arrange`), and slide-wide settings (`slide`). Splitting the old single
/// scrolling column into tabs separates per-object concerns from slide-wide
/// ones so the operator isn't scrolling past font controls to reach the
/// background.
///
/// Pure value type per project convention — the auto-switch rule is unit-
/// testable without SwiftUI.
enum InspectorTab: String, CaseIterable, Identifiable {
    case format, arrange, slide

    var id: String { rawValue }

    var title: String {
        switch self {
        case .format:  "Format"
        case .arrange: "Arrange"
        case .slide:   "Slide"
        }
    }

    /// The tab to focus when the canvas selection changes: `format` when an
    /// object is selected (jump to its styling), `slide` when nothing is
    /// (deselect → slide-wide settings). Consulted *only* on a selection
    /// change, so a manually chosen tab is otherwise left alone.
    static func onSelectionChange(hasSelection: Bool) -> InspectorTab {
        hasSelection ? .format : .slide
    }
}
