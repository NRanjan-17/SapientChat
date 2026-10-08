// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import SwiftUI

/// Measures the selected model on this device: settings, Run/Cancel,
/// progress, each run as it finishes, and the results.
struct BenchmarkView: View {
    @Bindable var viewModel: BenchmarkViewModel
    let makeSelector: (String, @escaping (String) -> Void) -> ModelSelectorViewModel
    /// Single Model / Compare, first in the setup column.
    var modeSwitch: BenchmarkModeSwitch?

    var body: some View {
        SetupResultsLayout {
            if let modeSwitch { modeSwitch }
            Section {
                if viewModel.availableModels.isEmpty {
                    LabeledContent("Model", value: viewModel.model)
                } else {
                    ModelPickerField(title: "Model", selection: viewModel.model, makeSelector: makeSelector) { alias in
                        viewModel.model = alias
                    }
                }
            } footer: {
                Text(viewModel.isRunning
                    ? "Locked while the benchmark runs."
                    : "A model a chat already has in memory is reused, not loaded again. Your conversations are kept.")
            }
            .disabled(viewModel.isRunning)

            BenchmarkSettingsSection(settings: $viewModel.settings)
                .disabled(viewModel.isRunning)

            BenchmarkRunSection(
                state: viewModel.state,
                canRun: viewModel.canRun,
                onRun: viewModel.run,
                onCancel: viewModel.cancel
            )
        } results: {
            if !viewModel.completedRuns.isEmpty && viewModel.isRunning {
                Section("Finished runs") {
                    ForEach(viewModel.completedRuns) { run in
                        BenchmarkRunRow(run: run)
                    }
                }
            }
            if let result = viewModel.result {
                BenchmarkResultsSection(result: result)
            } else if !viewModel.isRunning {
                Section {
                    ContentUnavailableView(
                        "No results yet",
                        systemImage: "gauge.with.dots.needle.67percent",
                        description: Text("Run a benchmark to measure decode speed, first-token time and memory on this device.")
                    )
                }
            }
        }
        .toolbar {
            if let result = viewModel.result {
                ToolbarItem(placement: .primaryAction) {
                    ReportShareMenu(
                        title: "Share",
                        fileName: PDFExporter.fileName("Benchmark", models: [viewModel.model.split(separator: "/").last.map(String.init) ?? viewModel.model], date: .now),
                        json: result.jsonText()
                    ) {
                        BenchmarkReportView(result: result, device: .current(), date: .now)
                    }
                }
            }
        }
    }
}

#Preview("Settings") {
    NavigationStack { BenchmarkView(viewModel: .preview, makeSelector: ChatListViewModel.preview.makeModelSelector) }
}

#Preview("Results") {
    NavigationStack { BenchmarkView(viewModel: .finishedPreview, makeSelector: ChatListViewModel.preview.makeModelSelector) }
}
