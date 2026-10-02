import SwiftUI

/// Measures the selected model on this device: settings, Run/Cancel,
/// progress and results.
struct BenchmarkView: View {
    @Bindable var viewModel: BenchmarkViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Model", value: viewModel.model)
                } footer: {
                    Text("Runs on the model the chat uses. Your conversation is kept.")
                }

                BenchmarkSettingsSection(settings: $viewModel.settings)
                    .disabled(viewModel.isRunning)

                BenchmarkRunSection(
                    state: viewModel.state,
                    canRun: viewModel.canRun,
                    onRun: viewModel.run,
                    onCancel: viewModel.cancel
                )

                if let result = viewModel.result {
                    BenchmarkResultsSection(result: result)
                }
            }
            .navigationTitle("Benchmark")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: close)
                }
                if let result = viewModel.result {
                    ToolbarItem(placement: .topBarLeading) {
                        ShareLink(item: result.jsonText(), preview: SharePreview("Benchmark results"))
                    }
                }
            }
            .interactiveDismissDisabled(viewModel.isRunning)
        }
        // iOS forbids GPU work in the background: stop between runs instead.
        .onChange(of: scenePhase) { _, phase in
            handleScenePhase(phase)
        }
    }

    private func handleScenePhase(_ phase: ScenePhase) {
        if phase != .active { viewModel.cancel() }
    }

    private func close() {
        viewModel.cancel()
        dismiss()
    }
}

#Preview("Settings") {
    BenchmarkView(viewModel: .preview)
}

#Preview("Results") {
    BenchmarkView(viewModel: .finishedPreview)
}
