import SwiftUI

/// Measures the selected model on this device: settings, Run/Cancel,
/// progress and results.
struct BenchmarkView: View {
    @Bindable var viewModel: BenchmarkViewModel

    var body: some View {
        Form {
            Section {
                if viewModel.availableModels.isEmpty {
                    LabeledContent("Model", value: viewModel.model)
                } else {
                    CompareModelPicker(title: "Model", models: viewModel.availableModels, selection: $viewModel.model)
                }
            } footer: {
                Text("A model a chat already has in memory is reused, not loaded again. Your conversations are kept.")
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

            if let result = viewModel.result {
                BenchmarkResultsSection(result: result)
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
    NavigationStack { BenchmarkView(viewModel: .preview) }
}

#Preview("Results") {
    NavigationStack { BenchmarkView(viewModel: .finishedPreview) }
}
