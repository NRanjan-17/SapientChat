// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 OpenHorizon Labs Pvt Ltd — Sapient Studio: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

/// `BenchmarkService` for SwiftUI previews: returns the sample result.
nonisolated struct PreviewBenchmarkService: BenchmarkService {
    func benchmark(
        model: String,
        settings: BenchmarkSettings,
        onProgress: @escaping @Sendable (BenchmarkProgress) -> Void
    ) async throws -> BenchmarkResult {
        for completed in 1...settings.totalRuns {
            try await Task.sleep(for: .milliseconds(400))
            onProgress(BenchmarkProgress(completed: completed, total: settings.totalRuns, lastRun: BenchmarkRunResult.samples[0]))
        }
        return .sample
    }
}
