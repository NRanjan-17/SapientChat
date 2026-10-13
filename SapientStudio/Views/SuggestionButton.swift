// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 OpenHorizon Labs Pvt Ltd — Sapient Studio: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import SwiftUI

/// One tappable starter prompt.
struct SuggestionButton: View {
    let text: String
    let onTap: (String) -> Void

    var body: some View {
        Button(action: tap) {
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .contentShape(.rect(cornerRadius: 16))
                .glassSurface(in: .rect(cornerRadius: 16), interactive: true)
        }
        .buttonStyle(.plain)
    }

    private func tap() {
        onTap(text)
    }
}
