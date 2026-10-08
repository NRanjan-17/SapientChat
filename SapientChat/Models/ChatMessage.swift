// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation

/// One bubble in the transcript (a value copy of a `StoredMessage`).
nonisolated struct ChatMessage: Identifiable, Equatable, Sendable {
    enum Role: String, Sendable {
        /// Instructions for the model; only API clients send these.
        case system
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    var text: String
    /// How the reply was generated (assistant messages measured in the app).
    var stats: ReplyStats?

    init(id: UUID = UUID(), role: Role, text: String, stats: ReplyStats? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.stats = stats
    }
}
