// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import SwiftUI

/// Shown above the composer while a chat's model gets ready: download
/// progress (with Cancel), "Loading into memory", or what went wrong
/// (with Retry).
struct ModelStatusCard: View {
    let status: ChatStatus
    let onCancel: () -> Void
    let onRetry: () -> Void

    var body: some View {
        switch status {
        case .downloading(let model, let progress):
            card {
                HStack {
                    Label("Downloading \(model)", systemImage: "arrow.down.circle")
                        .font(.subheadline.bold())
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .font(.subheadline)
                }
                DownloadProgressView(progress: progress)
                Text("First use only. Afterwards it loads offline.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .loading(let model):
            card {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading \(model) into memory…")
                        .font(.subheadline)
                }
            }
        case .failed(let problem):
            card {
                IconText(problem.title, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.orange)
                Text(problem.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if problem.canRetry {
                    Button(problem.retryTitle, systemImage: "arrow.clockwise", action: onRetry)
                        .font(.subheadline.bold())
                        .buttonStyle(.bordered)
                }
            }
        case .idle, .generating:
            EmptyView()
        }
    }

    private func card(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8, content: content)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: .rect(cornerRadius: 18))
            .padding(.horizontal)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

#Preview {
    VStack {
        ModelStatusCard(status: .downloading(model: "smollm2-1.7b", progress: DownloadProgress(downloadedBytes: 412_000_000, totalBytes: 1_060_000_000)), onCancel: {}, onRetry: {})
        ModelStatusCard(status: .loading(model: "smollm2-1.7b"), onCancel: {}, onRetry: {})
        ModelStatusCard(status: .failed(.classify("dns error: failed to lookup address", model: "smollm2-1.7b")), onCancel: {}, onRetry: {})
    }
}
