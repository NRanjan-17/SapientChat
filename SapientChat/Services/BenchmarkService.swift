// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

/// Measures a model on this device.
nonisolated protocol BenchmarkService: Sendable {
    /// Loads `model` if it isn't already, then runs `settings`. Reports
    /// progress after every run. Cancelling the calling task stops after the
    /// current run and returns what finished (`cancelled == true`).
    func benchmark(
        model: String,
        settings: BenchmarkSettings,
        onProgress: @escaping @Sendable (BenchmarkProgress) -> Void
    ) async throws -> BenchmarkResult
}
