import SwiftUI

/// One chat in the list: title, model and when it was last used.
struct ConversationRow: View {
    let conversation: Conversation

    private var modelName: String {
        conversation.modelAlias.split(separator: "/").last.map(String.init) ?? conversation.modelAlias
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(conversation.title)
                .font(.headline)
                .lineLimit(1)
            HStack {
                Label(modelName, systemImage: "cpu")
                    .labelStyle(.titleAndIcon)
                Spacer()
                Text(conversation.updatedAt, format: .relative(presentation: .named))
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}
