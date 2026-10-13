// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation

/// A rough token count for text. The engine exposes no tokenizer, so this
/// is the usual rule of thumb for English (about four characters a token);
/// code and other languages run higher. Always shown as "about".
nonisolated enum TokenEstimate {
    static let charactersPerToken = 4.0
    /// The engine's default window for models above 1.5B on a phone, and
    /// for the rest.
    static let largeModelWindow = 3072
    static let defaultWindow = 8192

    static func tokens(in text: String) -> Int {
        text.isEmpty ? 0 : max(1, Int((Double(text.count) / charactersPerToken).rounded(.up)))
    }

    /// The window `model` loads with: the user's pick, else the engine's default.
    static func window(for model: PhoneModel, picked: Int?) -> Int {
        picked ?? (model.billions > 1.5 ? largeModelWindow : defaultWindow)
    }

    /// Share of the window a prompt may fill; the rest is for the reply
    /// and for the estimate being off.
    static let promptShare = 0.75
    /// Tokens the chat template adds around each message, roughly.
    static let perMessageOverhead = 4

    /// `history` cut to what fits `window`, for chats longer than the model
    /// can read at once: system messages stay, then as many of the newest
    /// messages as fit, starting at a user message. The newest message is
    /// always kept. `dropped` is how many older messages were left out.
    static func fitting(_ history: [ChatMessage], window: Int) -> (history: [ChatMessage], dropped: Int) {
        func cost(_ message: ChatMessage) -> Int { tokens(in: message.text) + perMessageOverhead }
        let budget = Int(Double(window) * promptShare)
        guard history.reduce(0, { $0 + cost($1) }) > budget else { return (history, 0) }
        let system = history.filter { $0.role == .system }
        let turns = history.filter { $0.role != .system }
        var used = system.reduce(0) { $0 + cost($1) }
        var kept: [ChatMessage] = []
        for message in turns.reversed() {
            let next = cost(message)
            if !kept.isEmpty && used + next > budget { break }
            kept.insert(message, at: 0)
            used += next
        }
        // A window that opens on a reply confuses chat templates.
        while kept.count > 1, kept.first?.role == .assistant { kept.removeFirst() }
        return (system + kept, turns.count - kept.count)
    }

    /// "About 120 of 8,192 tokens", or "About 120 tokens" without a window.
    static func label(tokens: Int, window: Int?) -> String {
        guard let window else { return "About \(tokens.formatted()) tokens" }
        return "About \(tokens.formatted()) of \(window.formatted()) tokens"
    }
}
