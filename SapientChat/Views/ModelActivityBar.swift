// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import SwiftUI

/// A floating bar on the chat list while models download or load, so work
/// started in the model manager stays visible after it closes.
struct ModelActivityBar: View {
    let rows: [ModelManagerViewModel.Row]
    let onTap: () -> Void

    var body: some View {
        if let row = rows.first {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    ModelTile(model: row.model, size: 34)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title(for: row))
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        switch row.activity {
                        case .downloading(let progress):
                            ProgressView(value: progress.fraction ?? 0)
                                .tint(row.model.tint)
                            Text([progress.speedText, progress.remainingText].compactMap(\.self).joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        default:
                            Text("Loading into memory…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(12)
                .background(.regularMaterial, in: .rect(cornerRadius: 18))
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens Models")
        }
    }

    private func title(for row: ModelManagerViewModel.Row) -> String {
        let more = rows.count > 1 ? " + \(rows.count - 1) more" : ""
        return switch row.activity {
        case .downloading(let progress):
            "Downloading \(row.model.displayName)" + (progress.fraction.map { " · \(Int(($0 * 100).rounded()))%" } ?? "") + more
        default:
            "Loading \(row.model.displayName)" + more
        }
    }
}
