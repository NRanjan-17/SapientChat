// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

/// Saves and loads chats. Main-actor isolated: SwiftData's main context is.
protocol ConversationStore: AnyObject {
    /// All chats, most recently updated first.
    func conversations() -> [Conversation]
    func createConversation(model: String) -> Conversation
    func delete(_ conversation: Conversation)
    /// Appends a message at the end of `conversation` and returns it.
    @discardableResult
    func append(_ role: ChatMessage.Role, text: String, to conversation: Conversation) -> StoredMessage
    func remove(_ message: StoredMessage, from conversation: Conversation)
    /// Marks `conversation` as changed now and writes pending changes to disk.
    func touch(_ conversation: Conversation)
    /// Writes pending changes to disk.
    func save()
}
