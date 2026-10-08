// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import SwiftUI

/// Run/Cancel plus progress or the failure reason.
struct BenchmarkRunSection: View {
    let state: BenchmarkViewModel.State
    let canRun: Bool
    let onRun: () -> Void
    let onCancel: () -> Void

    var body: some View {
        Section {
            switch state {
            case .running(let progress):
                ProgressView(value: progress.fraction) {
                    Text("Run \(min(progress.completed + 1, progress.total)) of \(progress.total)")
                } currentValueLabel: {
                    if let run = progress.lastRun {
                        Text("Last run: \(run.decodeTokensPerSecond, format: .number.precision(.fractionLength(1))) tok/s")
                    }
                }
                Button("Cancel", role: .cancel, action: onCancel)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                runButton
            case .idle, .finished:
                runButton
            }
        } footer: {
            #if targetEnvironment(simulator)
            Text("Simulator numbers measure this Mac, not a phone.")
            #endif
        }
    }

    private var runButton: some View {
        Button("Run Benchmark", systemImage: "gauge.with.dots.needle.67percent", action: onRun)
            .disabled(!canRun)
    }
}

#Preview {
    Form {
        BenchmarkRunSection(
            state: .running(BenchmarkProgress(completed: 2, total: 4, lastRun: BenchmarkRunResult.samples[0])),
            canRun: false,
            onRun: {},
            onCancel: {}
        )
    }
}
