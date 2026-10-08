// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import SwiftUI

/// Menu commands, with keyboard shortcuts for a hardware keyboard on iPad
/// (hold ⌘ to see them): a new chat, stopping a reply, and the sections.
struct AppCommands: Commands {
    let viewModel: ChatListViewModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Chat") {
                viewModel.selectedTab = .chats
                viewModel.newChat()
            }
            .keyboardShortcut("n")
        }
        CommandMenu("Chat") {
            Button("Stop Generating") {
                viewModel.activeChat?.stop()
            }
            .keyboardShortcut(".")
            .disabled(viewModel.activeChat?.isGenerating != true)
        }
        CommandMenu("Go") {
            ForEach(Array(AppTab.allCases.enumerated()), id: \.element) { index, tab in
                Button(tab.title) { viewModel.selectedTab = tab }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
            }
        }
    }
}
