import SwiftUI

/// Saved chats, newest first, with new, rename and delete.
struct ChatListView: View {
    @Bindable var viewModel: ChatListViewModel
    @State private var renaming: Conversation?
    @State private var isRenaming = false
    @State private var newTitle = ""

    var body: some View {
        List(selection: $viewModel.selectedID) {
            ForEach(viewModel.conversations) { conversation in
                ConversationRow(conversation: conversation)
                    .tag(conversation.id)
                    .contextMenu {
                        Button("Rename", systemImage: "pencil") { startRenaming(conversation) }
                        Button("Delete", systemImage: "trash", role: .destructive) { viewModel.delete(conversation) }
                    }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) { viewModel.delete(conversation) }
                    }
            }
        }
        .overlay {
            if viewModel.conversations.isEmpty {
                ContentUnavailableView(
                    "No chats yet",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Tap the pencil to start one.")
                )
            }
        }
        .readableContentWidth(720)
        .navigationTitle("Chats")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Chat", systemImage: "square.and.pencil", action: viewModel.newChat)
            }
        }
        .alert("Rename Chat", isPresented: $isRenaming) {
            TextField("Title", text: $newTitle)
            Button("Rename", action: finishRenaming)
            Button("Cancel", role: .cancel) {}
        }
        .safeAreaInset(edge: .bottom) {
            if !viewModel.models.activeRows.isEmpty {
                ModelActivityBar(rows: viewModel.models.activeRows, onTap: showModels)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth, value: viewModel.models.activeRows.isEmpty)
    }

    private func startRenaming(_ conversation: Conversation) {
        newTitle = conversation.title
        renaming = conversation
        isRenaming = true
    }

    private func finishRenaming() {
        if let renaming { viewModel.rename(renaming, to: newTitle) }
        renaming = nil
    }

    /// Downloads and loads in progress live on the Models tab.
    private func showModels() {
        viewModel.selectedTab = .models
    }
}

#Preview {
    NavigationStack {
        ChatListView(viewModel: .preview)
    }
}
