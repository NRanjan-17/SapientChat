// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation

/// How one reply was generated, measured in the app as it streamed.
///
/// Speed counts text pieces as SAPIENT's stream delivers them, which is
/// close to but not exactly tokens (≈ tok/s). The Benchmark tab measures
/// exact tokens.
nonisolated struct ReplyStats: Codable, Equatable, Sendable {
    /// From asking for the reply to its first text (prompt prefill).
    var firstTokenMs: Int
    /// Pieces after the first ÷ the time they took; nil for one piece.
    var tokensPerSecond: Double?
    /// Text pieces received.
    var pieces: Int
    /// From asking for the reply to its last text.
    var durationMs: Int
    /// Download + load time, when this reply had to load the model.
    var loadMs: Int?
    var model: String
    var backend: String?

    /// "27.4 tok/s · 312 ms first token · 128 tokens · 4.8 s".
    var summary: String {
        var parts: [String] = []
        if let tokensPerSecond { parts.append("\(Format.rate(tokensPerSecond)) tok/s") }
        parts.append("\(firstTokenMs) ms first token")
        parts.append("\(pieces) tokens")
        parts.append(Duration.milliseconds(durationMs).formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 1))))
        return parts.joined(separator: " · ")
    }
}
