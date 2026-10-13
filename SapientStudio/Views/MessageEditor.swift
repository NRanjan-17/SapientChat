// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 OpenHorizon Labs Pvt Ltd — Sapient Studio: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import SwiftUI

/// Edits one of your messages in place, as on Claude: change the prompt,
/// then Send to answer again from there (later messages are replaced).
struct MessageEditor: View {
    @Binding var text: String
    let onCancel: () -> Void
    let onSend: () -> Void

    @FocusState private var isFocused: Bool

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            TextField("Edit your message", text: $text, axis: .vertical)
                .lineLimit(1...10)
                .focused($isFocused)
                .padding(12)
                .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.tint, lineWidth: 1.5))
            HStack(spacing: 8) {
                Text("Replies after this message will be replaced.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                Button("Send", action: onSend)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSend)
            }
            .controlSize(.small)
        }
        .padding(.leading, 40)
        .onAppear { isFocused = true }
    }
}

#Preview {
    MessageEditor(text: .constant("What is SAPIENT?"), onCancel: {}, onSend: {})
        .padding()
}
