// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import SwiftUI

/// A new chat: what runs it and a few prompts to start with.
struct EmptyChatView: View {
    let modelName: String
    var model: PhoneModel?
    var download: ModelDownload?
    var canChangeModel = true
    var onChangeModel: () -> Void = {}
    let onSuggestion: (String) -> Void

    static let suggestions = [
        "Explain how a transformer model works, simply.",
        "Write a haiku about running AI on a phone.",
        "Give me three tips for a productive morning.",
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                ContentUnavailableView {
                    Label("Chat with \(modelName)", systemImage: "sparkles")
                } description: {
                    Text("Everything runs on this \(UIDevice.current.model). Nothing you type leaves the device.")
                }
                if let model {
                    modelCard(model)
                        .padding(.horizontal)
                }
                VStack(spacing: 10) {
                    ForEach(Self.suggestions, id: \.self) { suggestion in
                        SuggestionButton(text: suggestion, onTap: onSuggestion)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .scrollDismissesKeyboard(.interactively)
        .readableContentWidth(640)
    }

    /// Which model answers and what the first message costs, with a way to
    /// pick another before anything downloads.
    private func modelCard(_ model: PhoneModel) -> some View {
        HStack(spacing: 12) {
            ModelTile(model: model, size: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.displayName)
                    .font(.headline)
                Text(downloadText(for: model))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Change", action: onChangeModel)
                .buttonStyle(.bordered)
                .disabled(!canChangeModel)
                .accessibilityLabel("Change Model")
        }
        .padding(12)
        .background(.fill.quaternary, in: .rect(cornerRadius: 14))
    }

    private func downloadText(for model: PhoneModel) -> String {
        switch download {
        case .downloaded: "On this device, works offline"
        case .partial: "Download paused, resumes with your first message"
        default: "\(model.downloadSizeText) download with your first message"
        }
    }
}

#Preview {
    EmptyChatView(modelName: "smollm2-135m-q4", onSuggestion: { _ in })
}
