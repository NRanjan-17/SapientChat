import SwiftUI

/// One message. Replies render Markdown (bold, italics, code, links) and
/// keep line breaks; long-press to copy or regenerate.
struct MessageBubble: View {
    let message: ChatMessage
    var canRegenerate = false
    var onRegenerate: () -> Void = {}

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isUser: Bool { message.role == .user }
    /// On wide screens replies are plain text, not a filled box, so long
    /// answers read like a page; your messages stay bubbles.
    private var isPlainReply: Bool { !isUser && horizontalSizeClass == .regular }

    var body: some View {
        content
            .textSelection(.enabled)
            .padding(.horizontal, isPlainReply ? 0 : 14)
            .padding(.vertical, isPlainReply ? 4 : 10)
            .foregroundStyle(isUser ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .background(
                isUser ? AnyShapeStyle(.tint) : isPlainReply ? AnyShapeStyle(.clear) : AnyShapeStyle(.fill.tertiary),
                in: .rect(cornerRadius: 18)
            )
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
            .padding(isUser ? .leading : .trailing, isPlainReply ? 0 : 40)
            .contextMenu {
                Button("Copy", systemImage: "doc.on.doc", action: copy)
                if canRegenerate {
                    Button(isUser ? "Retry" : "Regenerate", systemImage: "arrow.clockwise", action: onRegenerate)
                }
                if let stats = message.stats {
                    Section("Stats") {
                        if let speed = stats.tokensPerSecond {
                            Text("\(Format.rate(speed)) tok/s")
                        }
                        Text("First token in \(stats.firstTokenMs) ms")
                        Text("\(stats.pieces) tokens in \(Format.rate(Double(stats.durationMs) / 1000)) s")
                        if let loadMs = stats.loadMs {
                            Text("Model loaded in \(Format.rate(Double(loadMs) / 1000)) s")
                        }
                        if let backend = stats.backend {
                            Text(backend)
                        }
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(isUser ? "You" : "Assistant")
            .accessibilityValue(message.text)
    }

    /// Replies keep their structure (code, lists, headings); your own
    /// messages render as typed, with inline Markdown.
    @ViewBuilder private var content: some View {
        if isUser {
            Text(InlineMarkdown.attributed(message.text))
        } else {
            MarkdownContentView(text: message.text)
        }
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
