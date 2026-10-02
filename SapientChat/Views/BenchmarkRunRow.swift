import SwiftUI

/// One run: its label, decode rate, and TTFT / token count underneath.
struct BenchmarkRunRow: View {
    let run: BenchmarkRunResult

    private var title: String {
        run.isWarmup ? "Warm-up \(run.index)" : "Run \(run.index)"
    }

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                    .foregroundStyle(run.isWarmup ? .secondary : .primary)
                Spacer()
                Text("\(run.decodeTokensPerSecond, format: .number.precision(.fractionLength(1))) tok/s")
                    .monospacedDigit()
            }
            Text(details)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var details: String {
        var parts = ["TTFT \(run.ttftMs) ms", "\(run.tokens) tokens"]
        if run.hitEndOfTurn { parts.append("stopped early") }
        if let bytes = run.footprintBytes { parts.append(Format.bytes(bytes)) }
        return parts.joined(separator: " · ")
    }
}

#Preview {
    List(BenchmarkRunResult.samples) { run in
        BenchmarkRunRow(run: run)
    }
}
