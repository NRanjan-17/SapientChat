// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 OpenHorizon Labs Pvt Ltd — Sapient Studio: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import SwiftUI

/// Edits a chat's system prompt: instructions the model gets before the
/// chat's messages.
struct SystemPromptSheet: View {
    let onSave: (String) -> Void
    @State private var text: String
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss

    static let examples = [
        "Answer in one short paragraph.",
        "You are a senior Swift engineer. Reply with code first, then a brief explanation.",
        "Reply only with valid JSON.",
    ]

    init(text: String, onSave: @escaping (String) -> Void) {
        _text = State(initialValue: text)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("How the model should behave in this chat", text: $text, axis: .vertical)
                        .lineLimit(4...12)
                        .focused($isFocused)
                } footer: {
                    Text("Sent before this chat's messages, with every reply. It counts against the context window. Small models follow short, direct instructions best.")
                }
                Section("Examples") {
                    ForEach(Self.examples, id: \.self) { example in
                        Button(example) { text = example }
                            .foregroundStyle(.primary)
                    }
                }
                if !text.isEmpty {
                    Section {
                        Button("Clear", role: .destructive) { text = "" }
                    }
                }
            }
            .navigationTitle("System Prompt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(text)
                        dismiss()
                    }
                }
            }
            .onAppear { isFocused = text.isEmpty }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    SystemPromptSheet(text: "") { _ in }
}
