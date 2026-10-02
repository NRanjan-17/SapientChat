import SwiftUI

/// The scrolling transcript. Stays pinned to the newest message while a
/// reply streams in.
struct MessageListView: View {
    let messages: [ChatMessage]
    let canRegenerate: Bool
    let onRegenerate: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(messages) { message in
                    if message.role == .assistant && message.text.isEmpty {
                        TypingIndicator()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.opacity)
                    } else {
                        MessageBubble(
                            message: message,
                            canRegenerate: canRegenerate && message.id == messages.last?.id,
                            onRegenerate: onRegenerate
                        )
                        .transition(transition(for: message))
                    }
                }
            }
            .padding()
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.8), value: messages.count)
        }
        .defaultScrollAnchor(.bottom)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .scrollDismissesKeyboard(.interactively)
    }

    /// Your messages rise from the composer; replies fade in. Reduce Motion
    /// fades everything.
    private func transition(for message: ChatMessage) -> AnyTransition {
        if reduceMotion || message.role == .assistant {
            .opacity
        } else {
            .move(edge: .bottom).combined(with: .opacity)
        }
    }
}

#Preview {
    MessageListView(messages: ChatMessage.samples, canRegenerate: true, onRegenerate: {})
}
