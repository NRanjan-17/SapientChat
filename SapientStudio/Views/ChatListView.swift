// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 OpenHorizon Labs Pvt Ltd — Sapient Studio: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import SwiftUI

/// Saved chats, newest first, with new, rename and delete.
struct ChatListView: View {
    @Bindable var viewModel: ChatListViewModel
    @State private var renaming: Conversation?
    @State private var isRenaming = false
    @State private var newTitle = ""
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var pendingDelete: Conversation?
    @State private var isConfirmingDelete = false

    var body: some View {
        List(selection: $viewModel.selectedID) {
            ForEach(viewModel.conversations) { conversation in
                ConversationRow(conversation: conversation)
                    .tag(conversation.id)
                    .contextMenu {
                        Button("Rename", systemImage: "pencil") { startRenaming(conversation) }
                        Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete(conversation) }
                    }
                    // No full swipe: a chat can't be brought back.
                    .swipeActions(allowsFullSwipe: false) {
                        Button("Delete", systemImage: "trash") { confirmDelete(conversation) }
                            .tint(.red)
                    }
            }
        }
        .overlay {
            if viewModel.conversations.isEmpty {
                ContentUnavailableView {
                    Label("No chats yet", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text("Chats run on this device and are saved here.")
                } actions: {
                    // Beside the chat list, the wide layout's home screen
                    // already offers New Chat.
                    if horizontalSizeClass == .compact {
                        Button("New Chat", systemImage: "square.and.pencil", action: viewModel.newChat)
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .readableContentWidth(720)
        .navigationTitle("Chats")
        // A large title on the left, on the buttons' row (iPad split view
        // otherwise centres a small one).
        .toolbarTitleDisplayMode(.inlineLarge)
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
        .alert(deleteTitle, isPresented: $isConfirmingDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive, action: deletePending)
        } message: {
            Text("Its messages are removed from this device and can't be brought back.")
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

    private var deleteTitle: String {
        "Delete “\(pendingDelete?.title ?? Conversation.untitled)”?"
    }

    /// A chat with no messages has nothing to lose, so it goes at once.
    private func confirmDelete(_ conversation: Conversation) {
        guard !conversation.messages.isEmpty else {
            viewModel.delete(conversation)
            return
        }
        pendingDelete = conversation
        isConfirmingDelete = true
    }

    private func deletePending() {
        if let pendingDelete { viewModel.delete(pendingDelete) }
        pendingDelete = nil
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
