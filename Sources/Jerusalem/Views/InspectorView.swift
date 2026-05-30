import SwiftUI

/// The trailing inspector: the live-output mirror (current + next), panic controls,
/// transition choice, and selected-item metadata.
struct InspectorView: View {
    let item: Item?
    @Environment(LiveState.self) private var live

    var body: some View {
        @Bindable var live = live
        return Form {
            Section("Live") {
                liveBox
                nextRow
                panicRow
                Picker("Transition", selection: $live.transition) {
                    ForEach(TransitionStyle.allCases) { Text($0.label).tag($0) }
                }
            }

            Section("Item") {
                LabeledContent("Title", value: item?.title ?? "—")
                LabeledContent("Kind", value: item?.kind.displayName ?? "—")
                LabeledContent("Slides", value: item.map { "\($0.slides.count)" } ?? "—")
            }

            if let item, item.kind == .media {
                VideoSettingsSection(item: item)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var liveBox: some View {
        switch live.content {
        case .slide(let renderable):
            SlideStageView(renderable: renderable)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.red.opacity(0.8), lineWidth: 2))
        case .video(let cue):
            videoBox(cue)
        case .black:
            labelBox("BLACK")
        case .logo:
            labelBox("LOGO")
        case .empty:
            labelBox("Nothing live")
        }
    }

    @ViewBuilder private var nextRow: some View {
        if let next = live.nextProgramSlide {
            switch next.kind {
            case .slide(let renderable):
                LabeledContent("Next") {
                    RenderableSlideView(renderable: renderable)
                        .frame(width: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            case .video:
                LabeledContent("Next", value: "Video")
            }
        } else {
            LabeledContent("Next", value: "End")
        }
    }

    private var panicRow: some View {
        HStack {
            panicButton("Black", .black, systemImage: "rectangle.fill")
            panicButton("Clear", .clear, systemImage: "textformat.slash")
            panicButton("Logo", .logo, systemImage: "seal")
        }
    }

    private func panicButton(_ title: String, _ panic: LiveState.Panic, systemImage: String) -> some View {
        Button { live.setPanic(panic) } label: {
            Label(title, systemImage: systemImage).frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(live.panic == panic ? .red : nil)
    }

    private func labelBox(_ text: String) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(.black)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay { Text(text).font(.caption).foregroundStyle(.secondary) }
    }

    /// A muted preview of a live video clip (audio stays on the audience output).
    private func videoBox(_ cue: VideoCue) -> some View {
        var previewCue = cue
        previewCue.muted = true
        return ZStack {
            Color.black
            VideoPlayerView(cue: previewCue)
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.red.opacity(0.8), lineWidth: 2))
    }
}

/// Loop / mute / end-behavior controls for a selected video item, bound to the model.
/// (Takes effect the next time the item is armed.) Reused by the slide editor's
/// content rail for `.media` items.
struct VideoSettingsSection: View {
    @Bindable var item: Item

    var body: some View {
        Section("Video") {
            Toggle("Loop", isOn: $item.videoLoops)
            Toggle("Muted", isOn: $item.videoMuted)
            Picker("On end", selection: $item.videoEndBehavior) {
                ForEach(VideoEndBehavior.allCases) { Text($0.label).tag($0) }
            }
        }
    }
}

#Preview {
    InspectorView(item: nil).environment(LiveState())
}
