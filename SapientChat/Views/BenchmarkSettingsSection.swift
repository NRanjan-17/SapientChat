// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import SwiftUI

/// The editable benchmark settings.
struct BenchmarkSettingsSection: View {
    @Binding var settings: BenchmarkSettings
    /// Compare has a prompt for the answers too, so it calls this one
    /// "Benchmark prompt".
    var promptTitle = "Prompt"

    var body: some View {
        Section {
            Stepper("Tokens per run: \(settings.maxTokens)", value: $settings.maxTokens, in: 32...512, step: 32)
            Stepper("Measured runs: \(settings.runs)", value: $settings.runs, in: 1...10)
            Stepper("Warm-up runs: \(settings.warmup)", value: $settings.warmup, in: 0...3)
            Picker("Compute", selection: $settings.compute) {
                Text("As in Settings").tag(ComputePreference?.none)
                ForEach(ComputePreference.allCases.filter { $0 != .automatic }, id: \.self) { compute in
                    Text(compute.title).tag(ComputePreference?.some(compute))
                }
            }
        } header: {
            Text("Settings")
        } footer: {
            Text("Warm-up runs are reported but left out of the averages. Pick a Compute to measure it on its own (the model reloads on it).")
        }
        Section {
            TextField("What the model answers in each run", text: $settings.prompt, axis: .vertical)
                .lineLimit(3...6)
        } header: {
            Text(promptTitle)
        } footer: {
            Text("Ask for a long answer so every run reaches the token limit.")
        }
    }
}

#Preview {
    @Previewable @State var settings = BenchmarkSettings()
    Form {
        BenchmarkSettingsSection(settings: $settings)
    }
}
