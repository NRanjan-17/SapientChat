// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

/// Times one streaming reply. Feed it the moment each piece arrives (as an
/// offset from the request); it computes `ReplyStats`. A value type with
/// no clock of its own, so tests can drive it with exact times.
nonisolated struct ReplyStatsMeter: Sendable {
    private(set) var pieces = 0
    private var first: Duration?
    private var last: Duration?

    /// Records a piece that arrived `offset` after the request.
    mutating func record(at offset: Duration) {
        pieces += 1
        if first == nil { first = offset }
        last = offset
    }

    /// Speed so far: pieces after the first ÷ the time since the first.
    var tokensPerSecond: Double? {
        guard pieces >= 2, let first, let last else { return nil }
        let seconds = (last - first).seconds
        return seconds > 0 ? Double(pieces - 1) / seconds : nil
    }

    /// The finished reply's stats, or nil if nothing arrived.
    func stats(model: String, backend: String?, loadMs: Int?) -> ReplyStats? {
        guard let first, let last else { return nil }
        return ReplyStats(
            firstTokenMs: first.milliseconds,
            tokensPerSecond: tokensPerSecond,
            pieces: pieces,
            durationMs: last.milliseconds,
            loadMs: loadMs,
            model: model,
            backend: backend
        )
    }
}

nonisolated extension Duration {
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }

    var milliseconds: Int {
        Int((seconds * 1000).rounded())
    }
}
