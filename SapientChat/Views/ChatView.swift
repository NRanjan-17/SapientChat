// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import SwiftUI

/// One conversation. Layout only; state and logic live in `ChatViewModel`.
struct ChatView: View {
    @Bindable var viewModel: ChatViewModel
    let list: ChatListViewModel
    @State private var modelSelector: ModelSelectorViewModel?
    @State private var isShowingStats = false
    @State private var isShowingSettings = false
    @State private var isConfirmingDownload = false
    @State private var isEditingSystemPrompt = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            if viewModel.messages.isEmpty {
                EmptyChatView(
                    modelName: viewModel.modelName,
                    model: viewModel.model,
                    download: viewModel.modelDownload,
                    canChangeModel: !viewModel.isBusy,
                    onChangeModel: openModelSelector,
                    onSuggestion: sendSuggestion
                )
            } else {
                MessageListView(
                    messages: viewModel.messages,
                    canRegenerate: viewModel.canRegenerate,
                    onRegenerate: viewModel.regenerate,
                    canEdit: viewModel.canEdit,
                    onEdit: viewModel.edit
                )
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                ModelStatusCard(status: viewModel.status, onCancel: viewModel.stop, onRetry: viewModel.regenerate)
                ChatInputBar(
                draft: $viewModel.draft,
                placeholder: "Message",
                isBusy: viewModel.isBusy,
                isGenerating: viewModel.isGenerating,
                canSend: viewModel.canSend,
                onSend: send,
                onStop: viewModel.stop,
                footnote: contextFootnote,
                footnoteWarns: contextIsNearlyFull
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
                    if viewModel.model != nil {
                        Button("Model Settings…", systemImage: "slider.horizontal.3", action: showSettings)
                    }
                    Button(
                        viewModel.systemPrompt.isEmpty ? "System Prompt…" : "Edit System Prompt…",
                        systemImage: "text.quote"
                    ) { isEditingSystemPrompt = true }
                } label: {
                    // The name is already the subtitle; on iPhone the bar
                    // has no room to say it twice.
                    if horizontalSizeClass == .compact {
                        Label("Model: \(viewModel.modelName)", systemImage: "square.stack.3d.up")
                            .labelStyle(.iconOnly)
                    } else {
                        Label(viewModel.modelName, systemImage: "square.stack.3d.up")
                            .labelStyle(.titleAndIcon)
                    }
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
        .problemAlert($viewModel.alert) { _ in viewModel.regenerate() }
        .alert("Download \(viewModel.modelName)?", isPresented: $isConfirmingDownload) {
            Button("Download and Send", action: viewModel.send)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(downloadMessage)
        }
        .sheet(isPresented: $isEditingSystemPrompt) {
            SystemPromptSheet(text: viewModel.systemPrompt) { viewModel.systemPrompt = $0 }
        }
        .sheet(isPresented: $isShowingStats) {
            ModelStatsSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $isShowingSettings) {
            if let model = viewModel.model {
                ModelSettingsSheet(
                    model: model,
                    temperature: viewModel.temperature,
                    contextWindow: viewModel.contextWindow,
                    sampling: viewModel.sampling,
                    isLoaded: viewModel.modelDetails != nil
                ) { temperature, tokens, sampling in
                    viewModel.setSettings(temperature: temperature, contextWindow: tokens, sampling: sampling)
                }
            }
        }
    }

    private func showSettings() {
        isShowingSettings = true
        Task { await viewModel.refreshModelDetails() }
    }

    private func showStats() {
        isShowingStats = true
    }

    private func sendSuggestion(_ text: String) {
        viewModel.draft = text
        send()
    }

    /// Shown while typing, and whenever the chat has used most of its window.
    private var contextFootnote: String? {
        let dropped = viewModel.droppedFromContext
        if dropped > 0 {
            return "Long chat: the model no longer sees the oldest \(dropped == 1 ? "message" : "\(dropped) messages")"
        }
        let estimate = viewModel.contextEstimate
        guard !viewModel.draft.isEmpty || contextIsNearlyFull else { return nil }
        return TokenEstimate.label(tokens: estimate.tokens, window: estimate.window)
    }

    private var contextIsNearlyFull: Bool {
        if viewModel.droppedFromContext > 0 { return false }
        let estimate = viewModel.contextEstimate
        guard let window = estimate.window, window > 0 else { return false }
        return Double(estimate.tokens) / Double(window) >= 0.8
    }

    /// Asks before the first message starts a download, so its size (and
    /// cellular data) is never a surprise.
    private func send() {
        if viewModel.canSend && viewModel.needsDownloadToSend {
            isConfirmingDownload = true
        } else {
            viewModel.send()
        }
    }

    private var downloadMessage: String {
        var text = "This model isn't on your \(UIDevice.current.model) yet."
        if let model = viewModel.model {
            text += " Download: \(model.downloadSizeText), once. After that it works offline."
        }
        if NetworkMonitor.shared.isExpensive {
            text += " You're on cellular data."
        }
        return text
    }

    private func openModelSelector() {
        modelSelector = list.makeModelSelector(for: viewModel)
    }
}
