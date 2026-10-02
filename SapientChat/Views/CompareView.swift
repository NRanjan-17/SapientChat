import SwiftUI

/// Pick two models, run one prompt and a benchmark on each (one after the
/// other), and see answers and numbers side by side.
struct CompareView: View {
    @Bindable var viewModel: CompareViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    CompareModelPicker(title: "Model A", models: viewModel.models, selection: $viewModel.modelA)
                    CompareModelPicker(title: "Model B", models: viewModel.models, selection: $viewModel.modelB)
                } footer: {
                    Text("The models run one after the other, so only one is in memory and each gets the whole device.")
                }
                .disabled(viewModel.isRunning)

                Section("Prompt") {
                    TextField("Prompt", text: $viewModel.prompt, axis: .vertical)
                        .lineLimit(2...5)
                }
                .disabled(viewModel.isRunning)

                BenchmarkSettingsSection(settings: $viewModel.settings)
                    .disabled(viewModel.isRunning)

                CompareRunSection(
                    phase: viewModel.phase,
                    canRun: viewModel.canRun,
                    sameModel: viewModel.modelA == viewModel.modelB,
                    onRun: viewModel.run,
                    onCancel: viewModel.cancel
                )

                if !viewModel.results.isEmpty {
                    CompareResultsView(
                        results: viewModel.results,
                        names: viewModel.results.map { viewModel.displayName(of: $0.model) },
                        decodeDifferencePercent: viewModel.decodeDifferencePercent
                    )
                }
            }
            .navigationTitle("Compare Models")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: close)
                }
            }
            .interactiveDismissDisabled(viewModel.isRunning)
        }
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

#Preview {
    CompareView(viewModel: .preview)
}
