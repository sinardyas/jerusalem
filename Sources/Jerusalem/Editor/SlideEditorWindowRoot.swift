import SwiftUI
import SwiftData

extension Notification.Name {
    /// Posted when a slide-editor window closes so the operator window can
    /// re-arm `LiveState` with the (possibly edited) program.
    static let slideEditorDidClose = Notification.Name("id.soechi.slideEditorDidClose")
}

/// Root content for the dedicated slide-editor window (Phase 8.5). The window
/// scene carries the *item's* `PersistentIdentifier` (so the editor opens even
/// for an item with no slides yet — e.g. a brand-new song); this view re-resolves
/// the live `Item` from the shared model container's context and hosts
/// ``SlideEditorView``, opening it on the item's first slide (or none).
struct SlideEditorWindowRoot: View {
    let itemID: PersistentIdentifier?
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            if let itemID, let item = modelContext.model(for: itemID) as? Item {
                SlideEditorView(item: item, slideID: item.orderedSlides.first?.persistentModelID)
            } else {
                ContentUnavailableView("Item Unavailable",
                                       systemImage: "rectangle.slash",
                                       description: Text("This item could not be loaded for editing."))
            }
        }
        // Fire once per window close so the operator window re-arms the program.
        .onDisappear { NotificationCenter.default.post(name: .slideEditorDidClose, object: nil) }
    }
}
