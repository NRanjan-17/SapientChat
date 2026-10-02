import SwiftUI

/// One message. Replies render Markdown (bold, italics, code, links) and
/// keep line breaks; long-press to copy or regenerate.
struct MessageBubble: View {
    let message: ChatMessage
    var canRegenerate = false
    var onRegenerate: () -> Void = {}

    private var isUser: Bool { message.role == .user }

    private var content: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: message.text, options: options)) ?? AttributedString(message.text)
    }

    var body: some View {
        Text(content)
            .textSelection(.enabled)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .foregroundStyle(isUser ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .background(
                isUser ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.tertiary),
                in: .rect(cornerRadius: 18)
            )
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
            .padding(isUser ? .leading : .trailing, 40)
            .contextMenu {
                Button("Copy", systemImage: "doc.on.doc", action: copy)
                if canRegenerate {
                    Button(isUser ? "Retry" : "Regenerate", systemImage: "arrow.clockwise", action: onRegenerate)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(isUser ? "You" : "Assistant")
            .accessibilityValue(message.text)
    }

    private func copy() {
        UIPasteboard.general.string = message.text
    }
}

#Preview {
    VStack {
        ForEach(ChatMessage.samples) { message in
            MessageBubble(message: message)
        }
    }
    .padding()
}
