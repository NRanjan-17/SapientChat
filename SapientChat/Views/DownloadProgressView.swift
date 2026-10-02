import SwiftUI

/// A progress bar with "412 MB of 1.06 GB · 39%".
struct DownloadProgressView: View {
    let progress: DownloadProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let fraction = progress.fraction {
                ProgressView(value: fraction)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Downloading")
        .accessibilityValue(detail)
    }

    private var detail: String {
        if let fraction = progress.fraction {
            "\(progress.text) · \(Int((fraction * 100).rounded()))%"
        } else {
            progress.downloadedBytes > 0 ? progress.text : "Starting download…"
        }
    }
}
