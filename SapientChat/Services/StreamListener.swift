// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Sapient

/// Forwards engine tokens into an async stream. SAPIENT calls `onToken` on
/// its own thread; returning `false` stops generation.
nonisolated final class StreamListener: TokenListener, @unchecked Sendable {
    private let continuation: AsyncThrowingStream<String, any Error>.Continuation
    // Touched only from the engine's thread, one token at a time.
    private var loops = RepetitionGuard()

    init(continuation: AsyncThrowingStream<String, any Error>.Continuation) {
        self.continuation = continuation
    }

    func onToken(token: String) -> Bool {
        // `.terminated` means the consumer was cancelled (Stop, Clear,
        // backgrounding): tell the engine to stop.
        if case .terminated = continuation.yield(token) { return false }
        // Replies have no length cap, so a model stuck repeating itself
        // would otherwise run to the end of its context window.
        return !loops.isLooping(after: token)
    }
}

/// Notices a reply that has stopped saying anything new: the same short
/// run of tokens (up to `maxPeriod`) coming round again and again. Small
/// models do this ("hello hello hello…") instead of ending their turn.
nonisolated struct RepetitionGuard: Sendable {
    /// Longest repeating run looked for, in tokens.
    static let maxPeriod = 16
    /// How many times in a row a run must repeat…
    static let minRepeats = 12
    /// …and the fewest tokens that repetition must cover, so a short list
    /// of similar lines doesn't count.
    static let minSpan = 64

    private var recent: [String] = []

    /// Adds `token`; true once the reply's tail is one run on repeat.
    mutating func isLooping(after token: String) -> Bool {
        recent.append(token)
        let capacity = Self.maxPeriod * Self.minRepeats + Self.maxPeriod
        if recent.count > capacity { recent.removeFirst(recent.count - capacity) }
        for period in 1...Self.maxPeriod {
            let span = max(Self.minSpan, period * Self.minRepeats)
            guard recent.count >= span + period else { continue }
            let start = recent.count - span
            if (start..<recent.count).allSatisfy({ recent[$0] == recent[$0 - period] }) { return true }
        }
        return false
    }
}
