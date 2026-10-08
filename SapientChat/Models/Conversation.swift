// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation
import SwiftData

/// A saved chat. SwiftData persists it on-device automatically.
@Model
final class Conversation {
    static let untitled = "New Chat"

    var id: UUID
    var title: String
    /// Catalog alias of the model this chat uses.
    var modelAlias: String
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .cascade, inverse: \StoredMessage.conversation)
    var messages: [StoredMessage]

    init(modelAlias: String, title: String = Conversation.untitled, now: Date = .now) {
        id = UUID()
        self.title = title
        self.modelAlias = modelAlias
        createdAt = now
        updatedAt = now
        messages = []
    }

    /// Messages in the order they were written.
    var orderedMessages: [StoredMessage] {
        messages.sorted { $0.order < $1.order }
    }
}
