import SwiftUI

/// Benchmark tab: measure one model, or compare two side by side.
struct BenchmarkTab: View {
    let benchmark: BenchmarkViewModel
    let compare: CompareViewModel
    let makeSelector: (String, @escaping (String) -> Void) -> ModelSelectorViewModel
    @SceneStorage("benchmarkMode") private var mode = BenchmarkMode.single
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isRunning: Bool { benchmark.isRunning || compare.isRunning }

    /// Shown as the first row of the setup column, not as a band of its own.
    private var modeSwitch: BenchmarkModeSwitch {
        // Switching mid-run would hide the run's progress.
        BenchmarkModeSwitch(mode: $mode, isDisabled: isRunning)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .single: BenchmarkView(viewModel: benchmark, makeSelector: makeSelector, modeSwitch: modeSwitch)
                case .compare: CompareView(viewModel: compare, makeSelector: makeSelector, modeSwitch: modeSwitch)
                }
            }
            .navigationTitle("Benchmark")
            .toolbarTitleDisplayMode(.inlineLarge)
            // The two-form layout isn't one scroll view, and iPad then drew
            // no title at all (and the bar's row is shared with the tabs):
            // a large heading at the top left of the page, like Chats.
            .safeAreaInset(edge: .top, spacing: 0) {
                if horizontalSizeClass == .regular {
                    Text("Benchmark")
                        .font(.largeTitle.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 4)
                        .accessibilityAddTraits(.isHeader)
                }
            }
        }
    }
}

#Preview {
    BenchmarkTab(benchmark: .preview, compare: .preview, makeSelector: ChatListViewModel.preview.makeModelSelector)
}

/// Single Model / Compare, as a segmented control that sits on the form's
/// background (no card around it).
struct BenchmarkModeSwitch: View {
    @Binding var mode: BenchmarkMode
    let isDisabled: Bool

    var body: some View {
        Section {
            Picker("Mode", selection: $mode) {
                ForEach(BenchmarkMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(isDisabled)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }
}
