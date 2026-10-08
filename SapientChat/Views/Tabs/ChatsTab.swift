// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import SwiftUI

/// Chats tab: the chat list and the open chat, side by side on iPad and a
/// stack on iPhone.
struct ChatsTab: View {
    let viewModel: ChatListViewModel

    var body: some View {
        NavigationSplitView {
            ChatListView(viewModel: viewModel)
        } detail: {
            if let chat = viewModel.activeChat {
                ChatView(viewModel: chat, list: viewModel)
                    .id(chat.conversation.id)
            } else {
                ContentUnavailableView {
                    Label("No chat open", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text("Pick a chat or start a new one. Chats are saved on this device.")
                } actions: {
                    Button("New Chat", systemImage: "square.and.pencil", action: viewModel.newChat)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}
