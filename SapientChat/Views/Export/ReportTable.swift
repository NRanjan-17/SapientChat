// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import SwiftUI

/// A label/value table for PDF reports (Grid, which `ImageRenderer` draws).
struct ReportTable: View {
    let title: String
    let columns: [String]
    let rows: [[String]]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    ForEach(columns, id: \.self) { column in
                        Text(column).font(.caption.bold()).foregroundStyle(.secondary)
                    }
                }
                Divider()
                ForEach(rows, id: \.self) { row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(cell).monospacedDigit()
                        }
                    }
                }
            }
            .font(.subheadline)
        }
    }
}
