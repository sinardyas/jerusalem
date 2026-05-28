import SwiftUI
import AppKit

/// Phase 8.2.3 inline text edit. Mirrors the prototype's contenteditable: a
/// `TextEditor` floats over the element's frame, accepts the new text, and
/// commits on Enter / Escape / focus-loss.
///
/// Commit funnels through the editor's parent so the change goes through the
/// SwiftData undo manager (cmd-Z reverts the edit as a single step). Escape
/// cancels and restores the original text.
struct InlineTextEditOverlay: View {
    let initialText: String
    let frame: CGRect
    let font: Font
    let textColor: Color
    let alignment: TextAlignment
    var onCommit: (String) -> Void
    var onCancel: () -> Void

    @State private var draft: String
    @FocusState private var focused: Bool

    init(initialText: String,
         frame: CGRect,
         font: Font,
         textColor: Color,
         alignment: TextAlignment,
         onCommit: @escaping (String) -> Void,
         onCancel: @escaping () -> Void) {
        self.initialText = initialText
        self.frame = frame
        self.font = font
        self.textColor = textColor
        self.alignment = alignment
        self.onCommit = onCommit
        self.onCancel = onCancel
        _draft = State(initialValue: initialText)
    }

    var body: some View {
        // Block clicks reaching the canvas while editing.
        Color.black.opacity(0.001)
            .contentShape(Rectangle())
            .onTapGesture { commit() }
            .overlay(
                editor
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
            )
            .onAppear { focused = true }
            .background(escapeKeyCatcher)
    }

    @ViewBuilder private var editor: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.black.opacity(0.4))
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color.accentColor, lineWidth: 1.5)
            TextEditor(text: $draft)
                .focused($focused)
                .font(font)
                .foregroundStyle(textColor)
                .multilineTextAlignment(alignment)
                .scrollContentBackground(.hidden)
                .padding(6)
                .onSubmit(commit)
        }
    }

    /// Catches the Escape key (which `TextEditor` doesn't surface via
    /// `.onSubmit`) so the user can cancel a half-typed edit.
    private var escapeKeyCatcher: some View {
        Button(action: cancel) { Color.clear }
            .keyboardShortcut(.escape, modifiers: [])
            .frame(width: 0, height: 0)
            .opacity(0)
    }

    private func commit() {
        onCommit(draft)
    }

    private func cancel() {
        onCancel()
    }
}
