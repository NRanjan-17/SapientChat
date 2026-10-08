// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import SwiftUI

/// One side's value in a `CompareMetricRow`.
struct CompareValue: View {
    let side: String
    let value: String?

    var body: some View {
        VStack(alignment: .leading) {
            Text(side)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value ?? "—")
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
