import SwiftUI

/// Pick two models, run one prompt and a benchmark on each (one after the
/// other), and see answers and numbers side by side.
struct CompareView: View {
    @Bindable var viewModel: CompareViewModel
    let makeSelector: (String, @escaping (String) -> Void) -> ModelSelectorViewModel

    var body: some View {
        SetupResultsLayout {
            Section {
                ModelPickerField(title: "Model A", selection: viewModel.modelA, makeSelector: makeSelector, onSelect: viewModel.selectModelA)
                ModelPickerField(title: "Model B", selection: viewModel.modelB, makeSelector: makeSelector, onSelect: viewModel.selectModelB)
            } footer: {
                Text(viewModel.isRunning
                    ? "Locked while the comparison runs."
                    : "The models run one after the other, so each gets the whole device and the numbers stay fair.")
            }
            .disabled(viewModel.isRunning)

            Section("Answer prompt") {
                TextField("What both models answer", text: $viewModel.prompt, axis: .vertical)
                    .lineLimit(3...6)
            }
            .disabled(viewModel.isRunning)

            BenchmarkSettingsSection(settings: $viewModel.settings, promptTitle: "Benchmark prompt")
                .disabled(viewModel.isRunning)

            CompareRunSection(
                phase: viewModel.phase,
                canRun: viewModel.canRun,
                sameModel: viewModel.modelA == viewModel.modelB,
                onRun: viewModel.run,
                onCancel: viewModel.cancel
            )
        } results: {
            if viewModel.results.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No comparison yet",
                        systemImage: "square.split.2x1",
                        description: Text("Both answers and their numbers appear here, side by side.")
                    )
                }
            } else {
                CompareResultsView(
                    results: viewModel.results,
                    names: viewModel.results.map { viewModel.displayName(of: $0.model) },
                    prompt: viewModel.prompt,
                    decodeDifferencePercent: viewModel.decodeDifferencePercent
                )
            }
        }
    }
}

#Preview {
    NavigationStack { CompareView(viewModel: .preview, makeSelector: ChatListViewModel.preview.makeModelSelector) }
}
