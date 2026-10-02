import SwiftUI

/// The message composer: a rounded pill holding a growing text field and
/// the Send/Stop button. The border lights up in the accent colour while
/// focused. The field stays editable while a reply streams, so the
/// keyboard stays up and the next message can be drafted; sending waits
/// for the reply to finish.
struct ChatInputBar: View {
    @Binding var draft: String
    let placeholder: String
    let isBusy: Bool
    let isGenerating: Bool
    let canSend: Bool
    let onSend: () -> Void
    let onStop: () -> Void

    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Loading or downloading the model (busy, but no tokens yet).
    private var isLoading: Bool { isBusy && !isGenerating }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 24) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            TextField(isLoading ? "Loading model…" : placeholder, text: $draft, axis: .vertical)
                .lineLimit(1...6)
                .focused($isFocused)
                .padding(.leading, 16)
                .padding(.vertical, 12)
                .onSubmit(send)

            SendButton(
                mode: isGenerating ? .stop : .send,
                isEnabled: isGenerating || canSend,
                action: isGenerating ? onStop : send
            )
            .padding(.trailing, 4)
            .padding(.bottom, 2)
        }
        .background(.regularMaterial, in: shape)
        .overlay {
            shape.strokeBorder(
                isFocused ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator),
                lineWidth: isFocused ? 1.5 : 0.5
            )
        }
        .opacity(isLoading ? 0.75 : 1)
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: isFocused)
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: draft)
        .animation(reduceMotion ? nil : .smooth, value: isLoading)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func send() {
        onSend()
        // Keep the keyboard up for the next message.
        isFocused = true
    }
}

#Preview("Empty") {
    @Previewable @State var draft = ""
    VStack {
        Spacer()
        ChatInputBar(draft: $draft, placeholder: "Message smollm2-1.7b…", isBusy: false, isGenerating: false,
                     canSend: false, onSend: {}, onStop: {})
    }
}

#Preview("Generating") {
    @Previewable @State var draft = "Next question"
    VStack {
        Spacer()
        ChatInputBar(draft: $draft, placeholder: "Message smollm2-1.7b…", isBusy: true, isGenerating: true,
                     canSend: false, onSend: {}, onStop: {})
    }
}
