import SwiftUI

/// The printable report of a two-model comparison.
struct CompareReportView: View {
    let results: [ModelComparison]
    let names: [String]
    let prompt: String
    let decodeDifferencePercent: Double?
    let device: DeviceInfo
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ReportHeader(title: "Model comparison", subtitle: names.joined(separator: " vs "), device: device, date: date)

            ReportTable(title: "Numbers", columns: ["Metric"] + names, rows: [
                ["Decode"] + results.map { $0.benchmark.map { "\(Format.rate($0.meanDecodeTokensPerSecond)) tok/s" } ?? "—" },
                ["Time to first token"] + results.map { $0.benchmark.map { "\($0.meanTtftMs) ms" } ?? "—" },
                ["Prefill"] + results.map { $0.benchmark.map { "\(Format.rate($0.meanPrefillTokensPerSecond)) tok/s" } ?? "—" },
                ["Memory in use"] + results.map { $0.memoryInUseBytes.map(Format.bytes) ?? "—" },
                ["Model load"] + results.map { $0.benchmark.map { "\($0.loadTimeMs) ms" } ?? "—" },
            ])

            if let difference = decodeDifferencePercent, names.count == 2 {
                Text("\(names[1]) decodes \(Format.rate(abs(difference)))% \(difference >= 0 ? "faster" : "slower") than \(names[0]).")
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Prompt").font(.headline)
                Text(prompt).font(.subheadline)
            }

            ForEach(Array(zip(names, results)), id: \.1.id) { name, result in
                VStack(alignment: .leading, spacing: 6) {
                    Text("Answer · \(name)").font(.headline)
                    Text(result.answer.isEmpty ? "—" : result.answer).font(.subheadline)
                }
            }

            Text("The models ran one after the other, so each had the whole device. Decode counts tokens after the first; warm-up runs are excluded.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .background(.white)
    }
}
