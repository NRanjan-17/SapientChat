import SwiftUI

/// Chat list and the open chat: side by side on iPad, a stack on iPhone.
struct RootView: View {
    @Bindable var viewModel: ChatListViewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationSplitView {
            ChatListView(viewModel: viewModel)
        } detail: {
            if let chat = viewModel.activeChat {
                ChatView(viewModel: chat, list: viewModel)
                    .id(chat.conversation.id)
            } else {
                ContentUnavailableView {
                    Label("No chat open", systemImage: "bubble.left.and.text.bubble.right")
                } description: {
                    Text("Pick a chat or start a new one. Chats are saved on this device.")
                } actions: {
                    Button("New Chat", systemImage: "square.and.pencil", action: viewModel.newChat)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .safeAreaInset(edge: .top) {
            HandoffBanner(viewModel: viewModel.handoff)
        }
        .onOpenURL { url in
            if HandoffViewModel.handles(url) { viewModel.handoff.open(url) }
        }
        .task { await viewModel.device.observeThermal() }
        .onChange(of: scenePhase) { _, phase in
            handleScenePhase(phase)
        }
    }

    private func handleScenePhase(_ phase: ScenePhase) {
        if phase == .active {
            viewModel.server.appDidBecomeActive()
        } else {
            viewModel.appDidLeaveForeground()
        }
    }
}

#Preview {
    RootView(viewModel: .preview)
}
