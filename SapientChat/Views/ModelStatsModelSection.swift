// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import SwiftUI

/// What the chat's model is and how the engine loaded it.
struct ModelStatsModelSection: View {
    let model: PhoneModel?
    let name: String
    let details: LoadedModelDetails?

    var body: some View {
        Section {
            LabeledContent("Model", value: name)
            if let model {
                LabeledContent("Size", value: "\(model.sizeText) · \(model.formatChip.text)")
                LabeledContent("Estimated memory", value: Format.bytes(model.estimatedMemoryBytes))
            }
            if let details {
                LabeledContent("Runs on", value: details.backend)
                LabeledContent("Context window", value: "\(details.contextLength.formatted()) tokens")
                LabeledContent("Load time", value: Duration.milliseconds(Int(details.loadTimeMs)).formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 1))))
            }
        } header: {
            Text("Model")
        } footer: {
            if details == nil {
                Text("Not in memory right now. Send a message to load it.")
            }
        }
    }
}
