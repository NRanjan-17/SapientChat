// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import SwiftUI

/// Top-p, top-k and repetition penalty for a model. Each is off (the
/// engine's default) until its switch is turned on.
struct SamplingSection: View {
    @Binding var sampling: SamplingSettings
    /// Top-p and top-k do nothing at Precise (greedy decoding).
    let isSampling: Bool
    let isLoaded: Bool

    var body: some View {
        Section {
            OptionalSlider(
                title: "Top-p", value: $sampling.topP, fallback: Double(TemperatureStore.topP),
                range: SamplingSettings.topPRange, step: 0.05, fractionDigits: 2
            )
            .disabled(!isSampling)
            OptionalStepper(title: "Top-k", value: $sampling.topK, fallback: 40, range: SamplingSettings.topKRange, step: 5)
                .disabled(!isSampling)
            OptionalSlider(
                title: "Repetition penalty", value: $sampling.repetitionPenalty, fallback: 1.1,
                range: SamplingSettings.repetitionPenaltyRange, step: 0.05, fractionDigits: 2
            )
        } header: {
            Text("Sampling")
        } footer: {
            Text(footer)
        }
    }

    private var footer: String {
        var text = isSampling
            ? "Top-p and top-k limit which words the model may pick from. Repetition penalty discourages repeating itself."
            : "Top-p and top-k apply once the temperature is above Precise. Repetition penalty discourages repeating itself."
        text += " The engine takes no seed, so only Precise gives the same answer every time."
        if isLoaded { text += " Changing these reloads the model." }
        return text
    }
}

/// A switch that turns a setting on at `fallback`, with a slider under it.
private struct OptionalSlider: View {
    let title: String
    @Binding var value: Double?
    let fallback: Double
    let range: ClosedRange<Double>
    let step: Double
    let fractionDigits: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: isOn) {
                LabeledContent(title) {
                    Text(value.map { $0.formatted(.number.precision(.fractionLength(fractionDigits))) } ?? "Default")
                        .monospacedDigit()
                }
            }
            if value != nil {
                Slider(value: Binding { value ?? fallback } set: { value = $0 }, in: range, step: step) {
                    Text(title)
                }
            }
        }
    }

    private var isOn: Binding<Bool> {
        Binding { value != nil } set: { value = $0 ? fallback : nil }
    }
}

/// The same for a whole-number setting.
private struct OptionalStepper: View {
    let title: String
    @Binding var value: Int?
    let fallback: Int
    let range: ClosedRange<Int>
    let step: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: isOn) {
                LabeledContent(title) {
                    Text(value.map { $0.formatted() } ?? "Default")
                        .monospacedDigit()
                }
            }
            if value != nil {
                Stepper(value: Binding { value ?? fallback } set: { value = $0 }, in: range, step: step) {
                    Text("Keep the \(value ?? fallback) most likely")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var isOn: Binding<Bool> {
        Binding { value != nil } set: { value = $0 ? fallback : nil }
    }
}

#Preview {
    @Previewable @State var sampling = SamplingSettings(topP: 0.9)
    Form { SamplingSection(sampling: $sampling, isSampling: true, isLoaded: true) }
}
