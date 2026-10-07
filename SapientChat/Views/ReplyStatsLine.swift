import SwiftUI

/// The small grey line under a reply: speed, first token, length, time.
struct ReplyStatsLine: View {
    let stats: ReplyStats

    var body: some View {
        Label {
            Text(stats.summary)
        } icon: {
            Image(systemName: "gauge.with.dots.needle.33percent")
        }
        .labelStyle(.titleAndIcon)
        .font(.caption)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityLabel("Reply stats")
        .accessibilityValue(stats.summary)
    }
}

#Preview {
    ReplyStatsLine(stats: .sample)
        .padding()
}
