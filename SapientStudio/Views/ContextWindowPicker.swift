// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 OpenHorizon Labs Pvt Ltd — Sapient Studio: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import SwiftUI

/// Picks how many tokens a model keeps in view: its default, or 1K–8K.
struct ContextWindowPicker: View {
    let model: PhoneModel
    let isLoaded: Bool
    @Binding var tokens: Int?

    var body: some View {
        Section {
            Picker("Context window", selection: $tokens) {
                Text("Default").tag(Int?.none)
                ForEach(ContextWindowStore.choices, id: \.self) { choice in
                    Text("\(choice.formatted()) tokens").tag(Int?.some(choice))
                }
            }
        } footer: {
            Text(footer)
        }
    }

    private var footer: String {
        var text = "How much of the conversation \(model.displayName) can see at once. A bigger window remembers more but uses more memory. Default is 3,072 tokens for models above 1.5B, 8,192 otherwise."
        if isLoaded {
            text += " Changing it reloads the model."
        }
        return text
    }
}
