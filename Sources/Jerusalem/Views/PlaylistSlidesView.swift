import SwiftUI
import SwiftData

/// The detail pane when a playlist is selected: every slide in the playlist, in
/// running order, grouped under a sticky header per item title. Built from
/// ``LiveState/groupedProgram(for:)`` whose slide ids match the armed flat program,
/// so clicking a thumbnail goes live and the live slide highlights — exactly as in
/// the single-item ``SlideGridView``. Reuses ``SlideGridCell`` for each thumbnail.
struct PlaylistSlidesView: View {
    let playlist: Playlist
    var liveSlideID: PersistentIdentifier?
    var onActivate: (PersistentIdentifier) -> Void = { _ in }
    var onEdit: (PersistentIdentifier) -> Void = { _ in }

    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 18)]

    private var groups: [LiveState.ProgramGroup] { LiveState.groupedProgram(for: playlist) }
    private var slideCount: Int { groups.reduce(0) { $0 + $1.slides.count } }

    var body: some View {
        if groups.isEmpty {
            ContentUnavailableView {
                Label("No Slides", systemImage: "rectangle.on.rectangle.slash")
            } description: {
                Text("Add items to this playlist from the sidebar.")
            }
        } else {
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 18,
                          pinnedViews: [.sectionHeaders]) {
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.slides) { slide in
                                SlideGridCell(slide: slide,
                                              isLive: slide.id == liveSlideID,
                                              onActivate: onActivate,
                                              onEdit: onEdit)
                            }
                        } header: {
                            sectionHeader(group.title)
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle(playlist.name)
            .navigationSubtitle("\(slideCount) slide\(slideCount == 1 ? "" : "s")")
        }
    }

    /// A pinned section header naming the item the slides below belong to. The bar
    /// material keeps the title legible as slides scroll under it.
    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }
}
