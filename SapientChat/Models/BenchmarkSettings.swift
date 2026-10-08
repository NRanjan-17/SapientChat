// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

/// What to measure. Defaults match `sapient bench-llm`.
nonisolated struct BenchmarkSettings: Equatable, Sendable {
    var prompt = "Write a detailed explanation of how a CPU executes a program, step by step."
    var maxTokens = 128
    var runs = 3
    var warmup = 1
    /// Measure on this instead of the Compute setting; nil uses the setting.
    var compute: ComputePreference?

    var totalRuns: Int { runs + warmup }
}
