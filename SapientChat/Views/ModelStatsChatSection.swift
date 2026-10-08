// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import SwiftUI

/// Speed averages over this chat's replies, and the latest reply.
struct ModelStatsChatSection: View {
    let summary: ChatStatsSummary
    let last: ReplyStats?

    var body: some View {
        Section {
            if summary.replies == 0 {
                Text("No measured replies yet.")
                    .foregroundStyle(.secondary)
            } else {
                LabeledContent("Replies measured", value: summary.replies.formatted())
                if let average = summary.averageTokensPerSecond {
                    LabeledContent("Average speed", value: "\(Format.rate(average)) tok/s")
                }
                if let best = summary.bestTokensPerSecond {
                    LabeledContent("Best speed", value: "\(Format.rate(best)) tok/s")
                }
                if let firstToken = summary.averageFirstTokenMs {
                    LabeledContent("Average first token", value: "\(firstToken) ms")
                }
                if let last {
                    LabeledContent("Last reply", value: last.summary)
                }
            }
        } header: {
            Text("This chat")
        } footer: {
            Text("Measured as replies stream in; speed counts text pieces, which are close to tokens. The Benchmark tab measures exact tokens.")
        }
    }
}
