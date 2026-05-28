import SwiftUI
import SwiftData

/// The main detail area: a grid of rendered thumbnails for the active program's
/// slides. Program-driven (works for either a song/item or a whole playlist), so it
/// has no direct model dependency. Clicking a thumbnail takes it live;
/// right-click reveals "Edit Slide…" which opens the Phase 8 WYSIWYG editor.
struct SlideGridView: View {
    let title: String
    let subtitle: String
    let slides: [LiveState.ProgramSlide]
    var liveSlideID: PersistentIdentifier?
    var onActivate: (PersistentIdentifier) -> Void = { _ in }
    var onEdit: (PersistentIdentifier) -> Void = { _ in }

    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 18)]

    var body: some View {
        if slides.isEmpty {
            ContentUnavailableView {
                Label("No Slides", systemImage: "rectangle.on.rectangle.slash")
            } description: {
                Text("Select a song, Bible passage, or playlist to see its slides.")
            }
        } else {
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                    ForEach(slides) { slide in
                        Button { onActivate(slide.id) } label: { thumbnail(slide) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Go Live") { onActivate(slide.id) }
                                Button("Edit Slide…") { onEdit(slide.id) }
                            }
                    }
                }
                .padding(20)
            }
            .navigationTitle(title)
            .navigationSubtitle(subtitle)
        }
    }

    private func thumbnail(_ slide: LiveState.ProgramSlide) -> some View {
        let isLive = slide.id == liveSlideID
        return VStack(alignment: .leading, spacing: 6) {
            preview(slide.kind)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isLive ? Color.red : Color.gray.opacity(0.35),
                                  lineWidth: isLive ? 3 : 1))
                .overlay(alignment: .topLeading) {
                    if let label = slide.sectionLabel {
                        Text(label)
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(.black.opacity(0.55), in: Capsule())
                            .foregroundStyle(.white)
                            .padding(6)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if Self.hasMissingMedia(slide) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                            .padding(6)
                            .help("This slide references a file that isn't on disk.")
                    }
                }
            if isLive {
                Text("LIVE").font(.caption2.bold()).foregroundStyle(.red)
            }
        }
    }

    /// Surfaces a missing-file warning so the operator notices on Saturday,
    /// not Sunday. Uses ``MediaAudit`` so this stays a 1-line UI hook.
    private static func hasMissingMedia(_ slide: LiveState.ProgramSlide) -> Bool {
        switch slide.kind {
        case .slide(let renderable): return !MediaAudit.missingFiles(in: renderable).isEmpty
        case .video(let cue):        return !MediaAudit.isPresent(cue)
        }
    }

    @ViewBuilder
    private func preview(_ kind: LiveState.ProgramSlide.Kind) -> some View {
        switch kind {
        case .slide(let renderable) where renderable.backgroundVideo != nil:
            // Motion-background slide: show text over black + a film hint (no live
            // video in the grid, to keep it light).
            ZStack {
                Color.black
                RenderableSlideView(renderable: renderable)
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "film").font(.caption2).padding(5).foregroundStyle(.white.opacity(0.7))
            }
        case .slide(let renderable):
            RenderableSlideView(renderable: renderable)
        case .video:
            ZStack {
                Color.black
                Image(systemName: "film").font(.largeTitle).foregroundStyle(.white.opacity(0.7))
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
        }
    }
}

#Preview {
    SlideGridView(title: "Preview", subtitle: "0 slides", slides: [])
}
