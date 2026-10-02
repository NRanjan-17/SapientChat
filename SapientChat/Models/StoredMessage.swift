import Foundation
import SwiftData

/// One saved message of a `Conversation`.
@Model
final class StoredMessage {
    var id: UUID
    /// `ChatMessage.Role` raw value. Stored as a string so the schema does
    /// not depend on the enum's layout.
    var role: String
    var text: String
    var createdAt: Date
    /// Position in the conversation; `createdAt` alone can tie.
    var order: Int
    var conversation: Conversation?

    init(role: ChatMessage.Role, text: String, order: Int, now: Date = .now) {
        id = UUID()
        self.role = role.rawValue
        self.text = text
        createdAt = now
        self.order = order
    }

    var chatMessage: ChatMessage {
        ChatMessage(id: id, role: ChatMessage.Role(rawValue: role) ?? .assistant, text: text)
    }
}
