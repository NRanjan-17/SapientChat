// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 OpenHorizon Labs Pvt Ltd — Sapient Studio: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import SwiftUI

/// The editable benchmark settings.
struct BenchmarkSettingsSection: View {
    @Binding var settings: BenchmarkSettings
    /// Compare has a prompt for the answers too, so it calls this one
    /// "Benchmark prompt".
    var promptTitle = "Prompt"

    /// 32–512, plus the current value if it's set to something else.
    static func tokenChoices(including current: Int) -> [Int] {
        Set([32, 64, 128, 256, 384, 512] + [current]).sorted()
    }

    var body: some View {
        Section {
            // A menu, not a stepper: 32 to 512 is fifteen taps apart.
            Picker("Tokens per run", selection: $settings.maxTokens) {
                ForEach(Self.tokenChoices(including: settings.maxTokens), id: \.self) { tokens in
                    Text(tokens, format: .number).tag(tokens)
                }
            }
            Stepper(value: $settings.runs, in: 1...10) {
                LabeledContent("Measured runs", value: settings.runs, format: .number)
            }
            Stepper(value: $settings.warmup, in: 0...3) {
                LabeledContent("Warm-up runs", value: settings.warmup, format: .number)
            }
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
