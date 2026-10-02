import SwiftUI

/// One message: user messages on the right, replies on the left.
struct MessageBubble: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        Text(message.text.isEmpty ? "…" : message.text)
            .textSelection(.enabled)
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(
                isUser ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.quaternary),
                in: .rect(cornerRadius: 16)
            )
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
            .padding(isUser ? .leading : .trailing, 48)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(isUser ? "You" : "Assistant")
            .accessibilityValue(message.text)
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
