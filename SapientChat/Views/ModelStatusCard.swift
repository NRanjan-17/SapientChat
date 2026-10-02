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
        case .failed(let message):
            card {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                Button("Retry", systemImage: "arrow.clockwise", action: onRetry)
                    .font(.subheadline)
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
        ModelStatusCard(status: .failed("smollm2-1.7b needs about 2.8 GB."), onCancel: {}, onRetry: {})
    }
}
