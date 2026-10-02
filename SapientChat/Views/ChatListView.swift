import SwiftUI

/// Saved chats, newest first, with new/rename/delete plus Compare and
/// Models entry points.
struct ChatListView: View {
    @Bindable var viewModel: ChatListViewModel
    @State private var renaming: Conversation?
    @State private var isRenaming = false
    @State private var newTitle = ""
    @State private var compare: CompareViewModel?
    @State private var storage: ModelSelectorViewModel?

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
        .navigationTitle("Chats")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Chat", systemImage: "square.and.pencil", action: viewModel.newChat)
            }
            ToolbarItem(placement: .topBarLeading) {
                Menu("More", systemImage: "ellipsis.circle") {
                    Button("Compare Two Models", systemImage: "square.split.2x1", action: openCompare)
                    Button("Downloaded Models", systemImage: "internaldrive", action: openStorage)
                }
            }
        }
        .alert("Rename Chat", isPresented: $isRenaming) {
            TextField("Title", text: $newTitle)
            Button("Rename", action: finishRenaming)
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $compare) { compare in
            CompareView(viewModel: compare)
        }
        .sheet(item: $storage) { storage in
            ModelSelectorView(viewModel: storage)
        }
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

    private func openCompare() {
        compare = viewModel.makeCompareViewModel()
    }

    private func openStorage() {
        storage = viewModel.makeStorageViewModel()
    }
}

#Preview {
    NavigationStack {
        ChatListView(viewModel: .preview)
    }
}
