// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import SwiftUI

/// Summary, device details and per-run numbers of a finished benchmark.
struct BenchmarkResultsSection: View {
    let result: BenchmarkResult

    private let rate = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1))

    var body: some View {
        Section {
            LabeledContent("Decode") {
                Text("\(result.meanDecodeTokensPerSecond, format: rate) tok/s")
            }
            LabeledContent("Decode range") {
                Text("\(result.minDecodeTokensPerSecond, format: rate) – \(result.maxDecodeTokensPerSecond, format: rate) tok/s")
            }
            LabeledContent("Time to first token", value: "\(result.meanTtftMs) ms")
            LabeledContent("Prefill") {
                Text("\(result.meanPrefillTokensPerSecond, format: rate) tok/s")
            }
            if let peak = result.peakFootprintBytes {
                LabeledContent("Peak memory", value: Format.bytes(peak))
            }
        } header: {
            Text(result.cancelled ? "Results (cancelled early)" : "Results")
        } footer: {
            Text("Averages over \(result.runs.count) measured runs. Decode counts tokens after the first; peak memory includes loading the model.")
        }

        Section("Setup") {
            LabeledContent("Backend", value: result.backend)
            LabeledContent("Weights", value: result.isMemoryMapped ? "Memory-mapped" : "In memory")
            LabeledContent("Context window", value: "\(result.contextLength) tokens")
            LabeledContent("Prompt", value: "\(result.promptTokens) tokens")
            LabeledContent("Model load", value: "\(result.loadTimeMs) ms")
            LabeledContent("Thermal", value: "\(result.thermalStart) → \(result.thermalEnd)")
            LabeledContent("Engine", value: result.engineVersion)
        }

        Section("Runs") {
            ForEach(result.warmupRuns + result.runs) { run in
                BenchmarkRunRow(run: run)
            }
        }
    }
}

#Preview {
    Form {
        BenchmarkResultsSection(result: .sample)
    }
}
