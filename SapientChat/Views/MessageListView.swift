import SwiftUI

/// The scrolling transcript. Stays pinned to the newest message while a
/// reply streams in.
struct MessageListView: View {
    let messages: [ChatMessage]

    var body: some View {
        if messages.isEmpty {
            ContentUnavailableView(
                "Start a conversation",
                systemImage: "bubble.left.and.text.bubble.right",
                description: Text("Replies are generated on this device. The first message downloads the selected model.")
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(messages) { message in
                        MessageBubble(message: message)
                    }
                }
                .padding()
            }
            .defaultScrollAnchor(.bottom)
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
            .scrollDismissesKeyboard(.interactively)
        }
    }
}

#Preview {
    MessageListView(messages: ChatMessage.samples)
}
