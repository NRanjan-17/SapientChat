import Foundation
import SwiftData

/// `ConversationStore` on a SwiftData context. Every change is saved
/// straight away, so chats survive the app being killed.
final class SwiftDataConversationStore: ConversationStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func conversations() -> [Conversation] {
        let newestFirst = FetchDescriptor<Conversation>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        return (try? context.fetch(newestFirst)) ?? []
    }

    func createConversation(model: String) -> Conversation {
        let conversation = Conversation(modelAlias: model)
        context.insert(conversation)
        save()
        return conversation
    }

    func delete(_ conversation: Conversation) {
        context.delete(conversation)
        save()
    }

    @discardableResult
    func append(_ role: ChatMessage.Role, text: String, to conversation: Conversation) -> StoredMessage {
        let next = (conversation.messages.map(\.order).max() ?? -1) + 1
        let message = StoredMessage(role: role, text: text, order: next)
        conversation.messages.append(message)
        touch(conversation)
        return message
    }

    func remove(_ message: StoredMessage, from conversation: Conversation) {
        conversation.messages.removeAll { $0.id == message.id }
        context.delete(message)
        touch(conversation)
    }

    func touch(_ conversation: Conversation) {
        conversation.updatedAt = .now
        save()
    }

    func save() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            // Nothing sensible to show mid-stream; the next save retries.
            print("SapientChat: saving chats failed: \(error)")
        }
    }
}
