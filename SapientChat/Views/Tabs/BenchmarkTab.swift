import SwiftUI

/// Benchmark tab: measure one model, or compare two side by side.
struct BenchmarkTab: View {
    let benchmark: BenchmarkViewModel
    let compare: CompareViewModel
    let makeSelector: (String, @escaping (String) -> Void) -> ModelSelectorViewModel
    @SceneStorage("benchmarkMode") private var mode = BenchmarkMode.single

    private var isRunning: Bool { benchmark.isRunning || compare.isRunning }

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .single: BenchmarkView(viewModel: benchmark, makeSelector: makeSelector)
                case .compare: CompareView(viewModel: compare, makeSelector: makeSelector)
                }
            }
            .navigationTitle("Benchmark")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Mode", selection: $mode) {
                        ForEach(BenchmarkMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    // Switching mid-run would hide the run's progress.
                    .disabled(isRunning)
                }
            }
        }
    }
}

#Preview {
    BenchmarkTab(benchmark: .preview, compare: .preview, makeSelector: ChatListViewModel.preview.makeModelSelector)
}
