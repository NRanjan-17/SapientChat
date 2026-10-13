// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import SwiftUI

/// Picks a model's sampling temperature: Precise / Balanced / Creative, or
/// any value on the slider. The binding changes only when a drag ends or a
/// preset is tapped, so a model in memory reloads once, not on every step.
struct TemperaturePicker: View {
    let model: PhoneModel
    let isLoaded: Bool
    @Binding var temperature: Double?
    @State private var draft: Double = 0

    var body: some View {
        Section {
            HStack(spacing: 8) {
                ForEach(TemperatureStore.presets, id: \.name) { preset in
                    Button(preset.name) { commit(preset.value) }
                        .buttonStyle(.bordered)
                        .tint(temperature == preset.value ? .accentColor : .secondary)
                        .controlSize(.small)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Temperature")
                    Spacer()
                    Text(TemperatureStore.label(TemperatureStore.normalized(draft)))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: $draft, in: TemperatureStore.range, step: TemperatureStore.step) {
                    Text("Temperature")
                } minimumValueLabel: {
                    Image(systemName: "scope").accessibilityLabel("Precise")
                } maximumValueLabel: {
                    Image(systemName: "sparkles").accessibilityLabel("Creative")
                } onEditingChanged: { editing in
                    if !editing { commit(TemperatureStore.normalized(draft)) }
                }
            }
        } header: {
            Text("Temperature")
        } footer: {
            Text(footer)
        }
        .onAppear { draft = temperature ?? 0 }
        .onChange(of: temperature) { _, value in draft = value ?? 0 }
    }

    private var footer: String {
        var text = "Precise always gives \(model.displayName) the same answer to the same prompt, which suits small models best. Higher values vary the wording more but drift more too."
        if isLoaded {
            text += " Changing it reloads the model."
        }
        return text
    }

    private func commit(_ value: Double?) {
        draft = value ?? 0
        if value != temperature { temperature = value }
    }
}

/// A model's settings, from a chat or the Models tab: temperature for every
/// model, and the context window for models large enough to pick one.
struct ModelSettingsSheet: View {
    let model: PhoneModel
    let isLoaded: Bool
    let onSave: (_ temperature: Double?, _ contextWindow: Int?, _ sampling: SamplingSettings) -> Void
    @State private var temperature: Double?
    @State private var contextWindow: Int?
    @State private var sampling: SamplingSettings
    @Environment(\.dismiss) private var dismiss

    init(model: PhoneModel, temperature: Double?, contextWindow: Int?, sampling: SamplingSettings = SamplingSettings(),
         isLoaded: Bool,
         onSave: @escaping (_ temperature: Double?, _ contextWindow: Int?, _ sampling: SamplingSettings) -> Void) {
        self.model = model
        self.isLoaded = isLoaded
        self.onSave = onSave
        _temperature = State(initialValue: temperature)
        _contextWindow = State(initialValue: contextWindow)
        _sampling = State(initialValue: sampling)
    }

    var body: some View {
        NavigationStack {
            Form {
                TemperaturePicker(model: model, isLoaded: isLoaded, temperature: $temperature)
                SamplingSection(sampling: $sampling, isSampling: temperature != nil, isLoaded: isLoaded)
                if ContextWindowStore.isAdjustable(model) {
                    ContextWindowPicker(model: model, isLoaded: isLoaded, tokens: $contextWindow)
                }
            }
            .navigationTitle("Model Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(temperature, contextWindow, sampling)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    ModelSettingsSheet(model: TestPreviewModel.model, temperature: 0.7, contextWindow: nil, isLoaded: true) { _, _, _ in }
}

private enum TestPreviewModel {
    static let model = PhoneModel(alias: "openhorizon/qwen2.5-1.5b", repoId: "org/qwen", params: "1.5B", billions: 1.5)
}
