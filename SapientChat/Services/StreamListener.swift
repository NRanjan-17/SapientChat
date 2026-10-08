// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Sapient

/// Forwards engine tokens into an async stream. SAPIENT calls `onToken` on
/// its own thread; returning `false` stops generation.
nonisolated final class StreamListener: TokenListener {
    private let continuation: AsyncThrowingStream<String, any Error>.Continuation

    init(continuation: AsyncThrowingStream<String, any Error>.Continuation) {
        self.continuation = continuation
    }

    func onToken(token: String) -> Bool {
        // `.terminated` means the consumer was cancelled (Stop, Clear,
        // backgrounding): tell the engine to stop.
        if case .terminated = continuation.yield(token) { return false }
        return true
    }
}
