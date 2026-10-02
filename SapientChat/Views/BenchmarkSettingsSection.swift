import SwiftUI

/// The editable benchmark settings.
struct BenchmarkSettingsSection: View {
    @Binding var settings: BenchmarkSettings

    var body: some View {
        Section {
            Stepper("Tokens per run: \(settings.maxTokens)", value: $settings.maxTokens, in: 32...512, step: 32)
            Stepper("Measured runs: \(settings.runs)", value: $settings.runs, in: 1...10)
            Stepper("Warm-up runs: \(settings.warmup)", value: $settings.warmup, in: 0...3)
            TextField("Prompt", text: $settings.prompt, axis: .vertical)
                .lineLimit(2...5)
        } header: {
            Text("Settings")
        } footer: {
            Text("Warm-up runs are reported but left out of the averages. Ask for a long answer so every run reaches the token limit.")
        }
    }
}

#Preview {
    @Previewable @State var settings = BenchmarkSettings()
    Form {
        BenchmarkSettingsSection(settings: $settings)
    }
}
