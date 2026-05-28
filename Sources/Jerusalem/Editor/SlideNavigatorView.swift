import SwiftUI
import SwiftData

/// Left-rail slide picker for the editor sheet (Phase 8.2.1). Lists the parent
/// item's slides in order with a small thumbnail and section label, and exposes
/// a `+` button at the top that inserts a blank slide themed via the item.
/// Selection is two-way bound to the editor's currently-edited `Slide.id`.
struct SlideNavigatorView: View {
    @Bindable var item: Item
    @Binding var selection: PersistentIdentifier?
    var onAddSlide: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            List(selection: $selection) {
                ForEach(Array(item.orderedSlides.enumerated()), id: \.element.persistentModelID) { index, slide in
                    NavigatorRow(index: index, slide: slide)
                        .tag(slide.persistentModelID as PersistentIdentifier?)
                }
            }
            .listStyle(.sidebar)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Slides")
                .font(.headline)
            Spacer()
            Button(action: onAddSlide) {
                Image(systemName: "plus")
            }
            .help("Add a blank slide")
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

private struct NavigatorRow: View {
    let index: Int
    let slide: Slide

    var body: some View {
        HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .trailing)
            RenderableSlideView(renderable: RenderableSlide(slide))
                .frame(width: 96, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.gray.opacity(0.3), lineWidth: 1))
            VStack(alignment: .leading, spacing: 2) {
                Text(slide.sectionLabel ?? "Slide \(index + 1)")
                    .font(.callout)
                    .lineLimit(1)
                if slide.isManuallyEdited {
                    Text("Edited")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}
