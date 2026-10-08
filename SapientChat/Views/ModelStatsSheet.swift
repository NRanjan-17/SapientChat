// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import SwiftUI

/// The chat's model at a glance: what it is and how it runs on this
/// device, plus speed averages over this chat's replies.
struct ModelStatsSheet: View {
    let viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                ModelStatsModelSection(
                    model: viewModel.model,
                    name: viewModel.modelName,
                    details: viewModel.modelDetails
                )
                if let model = viewModel.model, ContextWindowStore.isAdjustable(model) {
                    ContextWindowPicker(model: model, isLoaded: viewModel.modelDetails != nil, tokens: contextWindow)
                        .disabled(viewModel.isBusy)
                }
                ModelStatsDeviceSection(device: viewModel.device, loadedModels: viewModel.loadedModelNames)
                ModelStatsChatSection(summary: viewModel.chatSummary, last: viewModel.lastReplyStats)
            }
            .navigationTitle("Model Stats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: close)
                }
            }
            .task { await viewModel.refreshModelDetails() }
            .refreshable { await viewModel.refreshModelDetails() }
        }
        .presentationDetents([.medium, .large])
    }

    private var contextWindow: Binding<Int?> {
        Binding { viewModel.contextWindow } set: { viewModel.setContextWindow($0) }
    }

    private func close() {
        dismiss()
    }
}
