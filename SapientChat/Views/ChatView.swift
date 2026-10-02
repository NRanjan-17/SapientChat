import SwiftUI

/// The chat screen. Layout only; all state and logic live in `ChatViewModel`.
struct ChatView: View {
    @Bindable var viewModel: ChatViewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            MessageListView(messages: viewModel.messages)
                .safeAreaInset(edge: .bottom) {
                    ChatInputBar(
                        draft: $viewModel.draft,
                        isBusy: viewModel.isBusy,
                        isGenerating: viewModel.isGenerating,
                        canSend: viewModel.canSend,
                        onSend: viewModel.send,
                        onStop: viewModel.stop
                    )
                }
                .navigationTitle("Sapient Chat")
                .navigationSubtitle(viewModel.statusText)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        ModelPickerView(models: viewModel.availableModels, selection: $viewModel.selectedModel)
                            .disabled(viewModel.isBusy)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear", systemImage: "trash", action: viewModel.clearConversation)
                            .disabled(!viewModel.canClear)
                    }
                }
        }
        .task { await viewModel.observeThermalPressure() }
        .onAppear(perform: handleAppear)
        .onChange(of: scenePhase) { _, phase in
            handleScenePhase(phase)
        }
    }

    private func handleAppear() {
        viewModel.handleLaunchArguments(ProcessInfo.processInfo.arguments)
    }

    private func handleScenePhase(_ phase: ScenePhase) {
        if phase != .active { viewModel.appDidLeaveForeground() }
    }
}

#Preview("Conversation") {
    ChatView(viewModel: .preview)
}

#Preview("Empty") {
    ChatView(viewModel: .emptyPreview)
}
