// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 OpenHorizon Labs Pvt Ltd — Sapient Studio: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

/// Benchmark progress: runs finished out of the total (warm-up included).
nonisolated struct BenchmarkProgress: Equatable, Sendable {
    let completed: Int
    let total: Int
    let lastRun: BenchmarkRunResult?

    var fraction: Double { total > 0 ? Double(completed) / Double(total) : 0 }
}
