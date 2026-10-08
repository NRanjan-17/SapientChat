// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import SwiftUI

/// A progress bar with "412 MB of 1.06 GB · 39%" and "8.2 MB/s · 2 min left".
struct DownloadProgressView: View {
    let progress: DownloadProgress
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let fraction = progress.fraction {
                ProgressView(value: fraction)
                    .tint(tint)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                Text(detail)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if let speed = progress.speedText {
                    IconText([speed, progress.remainingText].compactMap(\.self).joined(separator: " · "), systemImage: "speedometer")
                        .foregroundStyle(tint)
                }
            }
            .font(.caption)
            .monospacedDigit()
            .lineLimit(1)
            .contentTransition(.numericText())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Downloading")
        .accessibilityValue([detail, progress.speedText, progress.remainingText].compactMap(\.self).joined(separator: ", "))
    }

    private var detail: String {
        if let fraction = progress.fraction {
            "\(progress.text) · \(Int((fraction * 100).rounded()))%"
        } else {
            progress.downloadedBytes > 0 ? progress.text : "Starting download…"
        }
    }
}
