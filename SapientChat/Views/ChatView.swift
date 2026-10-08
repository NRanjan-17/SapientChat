// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import SwiftUI

/// One conversation. Layout only; state and logic live in `ChatViewModel`.
struct ChatView: View {
    @Bindable var viewModel: ChatViewModel
    let list: ChatListViewModel
    @State private var modelSelector: ModelSelectorViewModel?
    @State private var isShowingStats = false
    @State private var isShowingContextWindow = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

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
            // The same column as the messages on wide screens.
            .frame(maxWidth: 720)
        }
        .navigationTitle(viewModel.conversation.title)
        .navigationSubtitle(viewModel.statusText)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Change Model…", systemImage: "square.stack.3d.up", action: openModelSelector)
                    if let model = viewModel.model, ContextWindowStore.isAdjustable(model) {
                        Button("Context Window…", systemImage: "text.alignleft", action: showContextWindow)
                    }
                } label: {
                    Label(viewModel.modelName, systemImage: "square.stack.3d.up")
                        .labelStyle(.titleAndIcon)
                }
                .disabled(viewModel.isBusy)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Model Stats", systemImage: "chart.bar.xaxis", action: showStats)
            }
        }
        // On iPhone a chat gets the whole screen; on iPad it sits beside the
        // list, where the tabs stay reachable.
        .toolbarVisibility(horizontalSizeClass == .compact ? .hidden : .automatic, for: .tabBar)
        .sheet(item: $modelSelector) { selector in
            ModelSelectorView(viewModel: selector)
        }
        .sheet(isPresented: $isShowingStats) {
            ModelStatsSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $isShowingContextWindow) {
            if let model = viewModel.model {
                ContextWindowSheet(
                    model: model,
                    current: viewModel.contextWindow,
                    isLoaded: viewModel.modelDetails != nil,
                    onSave: viewModel.setContextWindow
                )
            }
        }
    }

    private func showContextWindow() {
        isShowingContextWindow = true
        Task { await viewModel.refreshModelDetails() }
    }

    private func showStats() {
        isShowingStats = true
    }

    private func sendSuggestion(_ text: String) {
        viewModel.draft = text
        viewModel.send()
    }

    private func openModelSelector() {
        modelSelector = list.makeModelSelector(for: viewModel)
    }
}
