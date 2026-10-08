// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Sapient
import Synchronization

/// Receives SAPIENT's per-run benchmark callbacks (on an engine thread) and
/// tells the engine to stop once `cancel()` is called.
nonisolated final class BenchmarkProgressListener: BenchmarkListener {
    private let cancelled = Atomic<Bool>(false)
    private let onProgress: @Sendable (BenchmarkProgress) -> Void

    init(onProgress: @escaping @Sendable (BenchmarkProgress) -> Void) {
        self.onProgress = onProgress
    }

    func cancel() {
        cancelled.store(true, ordering: .relaxed)
    }

    func onRun(run: BenchmarkRun, completed: UInt32, total: UInt32) -> Bool {
        onProgress(BenchmarkProgress(completed: Int(completed), total: Int(total), lastRun: BenchmarkRunResult(run)))
        return !cancelled.load(ordering: .relaxed)
    }
}

nonisolated extension BenchmarkRunResult {
    init(_ run: BenchmarkRun) {
        self.init(
            index: Int(run.index),
            isWarmup: run.warmup,
            ttftMs: run.ttftMs,
            elapsedMs: run.elapsedMs,
            tokens: Int(run.tokens),
            decodeTokensPerSecond: run.decodeTokensPerSec,
            prefillTokensPerSecond: run.prefillTokensPerSec,
            hitEndOfTurn: run.hitEos,
            footprintBytes: run.footprintBytes
        )
    }
}
