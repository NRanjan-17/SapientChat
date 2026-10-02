import SwiftUI

/// The scrolling transcript. Stays pinned to the newest message while a
/// reply streams in.
struct MessageListView: View {
    let messages: [ChatMessage]
    let canRegenerate: Bool
    let onRegenerate: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(messages) { message in
                    if message.role == .assistant && message.text.isEmpty {
                        TypingIndicator()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        MessageBubble(
                            message: message,
                            canRegenerate: canRegenerate && message.id == messages.last?.id,
                            onRegenerate: onRegenerate
                        )
                    }
                }
            }
            .padding()
        }
        .defaultScrollAnchor(.bottom)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .scrollDismissesKeyboard(.interactively)
    }
}

#Preview {
    MessageListView(messages: ChatMessage.samples, canRegenerate: true, onRegenerate: {})
}
