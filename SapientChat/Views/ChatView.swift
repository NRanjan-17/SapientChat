import SwiftUI

/// One conversation. Layout only; state and logic live in `ChatViewModel`.
struct ChatView: View {
    @Bindable var viewModel: ChatViewModel
    let list: ChatListViewModel
    @State private var benchmark: BenchmarkViewModel?
    @State private var modelSelector: ModelSelectorViewModel?

    var body: some View {
        Group {
            if viewModel.messages.isEmpty {
                EmptyChatView(modelName: viewModel.modelName, onSuggestion: sendSuggestion)
            } else {
                MessageListView(
                    messages: viewModel.messages,
                    canRegenerate: viewModel.canRegenerate,
                    onRegenerate: viewModel.regenerate
                )
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                ModelStatusCard(status: viewModel.status, onCancel: viewModel.stop, onRetry: viewModel.regenerate)
                ChatInputBar(
                draft: $viewModel.draft,
                placeholder: "Message \(viewModel.modelName)…",
                isBusy: viewModel.isBusy,
                isGenerating: viewModel.isGenerating,
                canSend: viewModel.canSend,
                onSend: viewModel.send,
                onStop: viewModel.stop
                )
            }
            .animation(.smooth, value: viewModel.status)
        }
        .navigationTitle(viewModel.conversation.title)
        .navigationSubtitle(viewModel.statusText)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(viewModel.modelName, systemImage: "cpu", action: openModelSelector)
                    .labelStyle(.titleAndIcon)
                    .disabled(viewModel.isBusy)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Benchmark", systemImage: "gauge.with.dots.needle.67percent", action: openBenchmark)
                    .disabled(viewModel.isBusy)
            }
        }
        .sheet(item: $benchmark) { benchmark in
            BenchmarkView(viewModel: benchmark)
        }
        .sheet(item: $modelSelector) { selector in
            ModelSelectorView(viewModel: selector)
        }
    }

    private func sendSuggestion(_ text: String) {
        viewModel.draft = text
        viewModel.send()
    }

    private func openBenchmark() {
        benchmark = viewModel.makeBenchmarkViewModel()
    }

    private func openModelSelector() {
        modelSelector = list.makeModelSelector(for: viewModel)
    }
}
