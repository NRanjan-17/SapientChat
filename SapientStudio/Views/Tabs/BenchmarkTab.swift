// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 OpenHorizon Labs Pvt Ltd — Sapient Studio: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import SwiftUI

/// Benchmark tab: measure one model, or compare two side by side.
struct BenchmarkTab: View {
    let benchmark: BenchmarkViewModel
    let compare: CompareViewModel
    let makeSelector: (String, @escaping (String) -> Void) -> ModelSelectorViewModel
    var history: BenchmarkHistory?
    var promptSets: PromptSetsViewModel?
    @State private var isShowingHistory = false
    @SceneStorage("benchmarkMode") private var mode = BenchmarkMode.single

    private var isRunning: Bool { benchmark.isRunning || compare.isRunning || promptSets?.isRunning == true }

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
                case .promptSets:
                    if let promptSets {
                        PromptSetsView(viewModel: promptSets, makeSelector: makeSelector, modeSwitch: modeSwitch)
                    }
                }
            }
            .toolbar {
                if history != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("History", systemImage: "clock.arrow.circlepath") { isShowingHistory = true }
                    }
                }
            }
            .sheet(isPresented: $isShowingHistory) {
                if let history { BenchmarkHistoryView(history: history) }
            }
            .scrollEdgeEffectStyle(.hard, for: .bottom)
            .navigationTitle("Benchmark")
            .toolbarTitleDisplayMode(.inlineLarge)
            .pageTitle("Benchmark")
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
