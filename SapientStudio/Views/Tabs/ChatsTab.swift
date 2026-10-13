// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 OpenHorizon Labs Pvt Ltd — Sapient Studio: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

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
                    .background { AmbientBackground() }
            } else {
                WelcomeView(viewModel: viewModel)
                    .background { AmbientBackground() }
            }
        }
    }
}
